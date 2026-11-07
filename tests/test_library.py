"""Pure Lua 5.2 controls for the private MIR5 Library slice, not native evidence."""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LibraryTests(unittest.TestCase):
    def test_outer_pages_reserve_the_authored_title_and_tab_height_budget(self):
        self.lua.execute(r'''
          boot()
          player.display_resolution,player.display_scale={width=2560,height=1440},1.25
          local root=library.open(player,{selected=gear.name,query="gear"})
          local tabs=root.mir_library_tabs
          local function check_pages()
            -- Published 4.7.3's renderer reserves 112 logical pixels for the
            -- title, tabs and frame. Its accepted page budget is independent
            -- of the candidate and of the observed six-pixel overrun.
            local maximum=math.max(120,root.style.maximal_height-112)
            for _,name in ipairs({"research_page","queue_content","settings_content","help_content"}) do
              local page=tabs["mir_library_"..name]
              assert(page.style.maximal_height<=maximum,
                "outer page must reserve the authored title, tabs and frame height")
              assert(page.vertical_scroll_policy=="auto" and page.horizontal_scroll_policy=="never")
            end
          end
          check_pages()
          for _=1,6 do
            library.on_gui_click({player_index=1,element=root.mir_library_title.mir_library_layout_smaller})
            assert(player.gui.screen.mir_research_browser==root and root.mir_library_tabs==tabs)
            check_pages()
          end
          assert(root.style.maximal_width==640 and root.style.maximal_height==480)
          for _,tab in ipairs({"settings","queue","help","research"}) do
            assert(library.open(player,{tab=tab})==root)
            check_pages()
          end
          assert(storage.mir_library.players[1].query=="gear"
            and storage.mir_library.players[1].selected==gear.name)
        ''')

    def test_normal_research_details_use_full_height_without_a_toolbar_or_unlimited_cap_paragraph(self):
        self.lua.execute('''
          boot()
          player.display_resolution,player.display_scale={width=2560,height=1440},1.25
          local model=require("presentation.library_model")
          local original=model.rows
          model.rows=function(...)
            local rows=original(...);rows[1].cap=nil;rows[1].cap_state="unlimited";return rows
          end
          prototypes={item={["automation-science-pack"]={valid=true,name="automation-science-pack",localised_name="Automation science pack"}}}
          model.detail=function()return {cost={count=16000,energy=3600,
            ingredients={{name="automation-science-pack",amount=1}}},effects={},prerequisites={}} end
          local queue,current,progress=player.force.research_queue,player.force.current_research,player.force.research_progress
          local root=library.open(player,{selected=gear.name})
          local body=research_content(root)
          local left=body.mir_library_list_pane
          assert(left.type=="flow" and left.direction=="vertical")
          assert(body._children[1]==left and body._children[2]==body.mir_library_detail,
            "no toolbar row may displace the selected detail below the list header")
          local actions=left.mir_library_actions
          assert(actions.type=="table" and actions.column_count==5)
          assert(actions.mir_library_hide and actions.mir_library_inspect_settings
            and actions.mir_library_open_native and actions.mir_library_close)
          assert(actions.mir_library_close.type=="sprite-button" and actions.mir_library_close.tooltip[1]=="mir-browser.close")
          assert(body.mir_library_detail.style.maximal_height==body.style.maximal_height)
          local facts=body.mir_library_detail.mir_library_research_facts
          assert(facts.mir_library_detail_cap==nil and facts.mir_library_detail_level.tooltip[1]=="mir-browser.cap-unlimited")
          assert(facts.mir_library_science_icons and facts.mir_library_production_check)
          assert(player.force.research_queue==queue and player.force.current_research==current
            and player.force.research_progress==progress)
          player.display_resolution={width=1280,height=720}
          library.close(player)
          root=library.open(player,{selected=gear.name})
          left=research_content(root).mir_library_list_pane
          actions=left.mir_library_actions
          assert(actions.column_count==2 and actions.mir_library_inspect_settings.style.maximal_width>100,
            "narrow list headers wrap actions rather than clipping the Settings label")
          assert(left.mir_library_results.style.maximal_height+92<=left.style.maximal_height)
        ''')

    def test_debug_sharing_guidance_stays_on_the_export_without_a_clipped_duplicate_footer(self):
        self.lua.execute('''
          helpers={write_file=function() error("opening Debug exported a file") end}
          boot()
          local page=library.open(player,{tab="help"}).mir_library_tabs.mir_library_help_content
          local panel=debug_report(page)
          assert(panel.mir_library_export_privacy==nil)
          assert(panel.mir_library_report_local.caption[1]=="mir-browser.report-local")
          assert(panel.mir_library_report_local.tooltip[1]=="mir-browser.export-sharing-guidance")
          assert(panel.mir_library_export_diagnostics.tooltip[4][1]=="mir-browser.export-sharing-guidance")
          local preview=panel.mir_library_report_preview
          panel.add{type="label",name="mir_library_export_privacy",caption={"mir-browser.export-sharing-guidance"}}
          panel.mir_library_report_local.tooltip=nil
          panel.mir_library_export_diagnostics.tooltip={"mir-browser.export-diagnostics-tooltip"}
          library.open(player,{tab="help"})
          assert(panel.mir_library_export_privacy==nil and panel.mir_library_report_preview==preview)
          assert(panel.mir_library_report_local.tooltip[1]=="mir-browser.export-sharing-guidance")
          assert(panel.mir_library_export_diagnostics.tooltip[4][1]=="mir-browser.export-sharing-guidance")
        ''')

    def test_queue_restores_the_original_numbered_full_height_native_projection(self):
        self.lua.execute('''
          boot()
          player.display_resolution,player.display_scale={width=2560,height=1440},1.25
          local queue,current,progress=player.force.research_queue,player.force.current_research,player.force.research_progress
          local root=library.open(player,{tab="queue"})
          local page=root.mir_library_tabs.mir_library_queue_content
          local list=page.mir_library_queue_list
          assert(page.mir_library_queue_heading.caption[1]=="mir-browser.queue")
          assert(list.items[1][2]=="1. " and list.items[1][3]==gear.localised_name)
          assert(list.style.minimal_height==page.style.maximal_height-130 and list.style.minimal_width==root.style.maximal_width-64)
          assert(player.force.research_queue==queue and player.force.current_research==current
            and player.force.research_progress==progress)
        ''')

    def test_debug_restores_original_sections_and_two_panes_without_an_export_on_open(self):
        self.lua.execute('''
          helpers={write_file=function() error("opening Debug exported a file") end}
          boot()
          player.display_resolution,player.display_scale={width=2560,height=1440},1.25
          local root=library.open(player,{tab="help"})
          local page=root.mir_library_tabs.mir_library_help_content
          local panes=page.mir_library_help_panes
          assert(panes.type=="flow" and panes.direction=="horizontal")
          local tools,report=panes.mir_library_help_tools,panes.mir_library_report_panel
          assert(tools.type=="scroll-pane" and tools.horizontal_scroll_policy=="never")
          for _,name in ipairs({"installation","report_options","configuration","layout","startup_crash"}) do
            assert(tools["mir_library_help_"..name.."_divider"].type=="line")
            assert(tools["mir_library_help_"..name].style.font=="default-bold")
          end
          assert(report.mir_library_report_preview.read_only and report.mir_library_report_preview.word_wrap)
          assert(report.mir_library_report_preview.style.minimal_height>400 and page.mir_library_help_summary==nil)
          local preview=report.mir_library_report_preview
          library.open(player,{tab="research"});library.open(player,{tab="help"})
          assert(page.mir_library_help_panes==panes and report.mir_library_report_preview==preview)
          local foreign=page.add{type="button",name="mir_library_report_select"}
          library.on_gui_click{player_index=1,element=foreign}
          assert(preview.focused~=true,"same-named button outside the report panel gained authority")
        ''')

    def test_research_controls_match_the_original_full_width_search_and_upper_labels(self):
        self.lua.execute('''
          boot()
          player.display_resolution={width=2560,height=1440};player.display_scale=1.25
          local root=library.open(player,{search="gear",selected=gear.name})
          local filters=research_filters(root)
          assert(filters.type=="flow" and filters.direction=="vertical")
          local query=filters.mir_library_query
          assert(query.style.maximal_width==root.style.maximal_width-64,
            "the original search uses the available window width")
          local grid=filters.mir_library_filter_grid
          assert(grid.type=="table" and grid.column_count==2)
          local order={"family","status","mode","sort","visibility"}
          for i,name in ipairs(order) do
            local box=grid["mir_library_"..name.."_field"]
            assert(grid._children[i]==box and box.direction=="vertical")
            assert(box._children[1]==box["mir_library_"..name.."_label"]
              and box._children[2]==box["mir_library_"..name])
            assert(box["mir_library_"..name.."_label"].visible==true)
          end
          assert(research_content(root).mir_library_list_pane.mir_library_results.items[1][2]=="[img=technology/"..gear.name.."] ")
          assert(research_content(root).mir_library_list_pane.mir_library_results.items[1][3]==gear.localised_name)
          query.text="gears"
          library.on_gui_text_changed({player_index=1,element=query})
          assert(research_filters(root)==filters and filters.mir_library_query==query and query.text=="gears")
          local family=storage.mir_library.players[1].family
          local flat=filters.add{type="drop-down",name="mir_library_family",selected_index=3}
          library.on_gui_selection_state_changed{player_index=1,element=flat}
          assert(storage.mir_library.players[1].family==family,
            "a same-named flat field must not bypass the owned grid/field ancestry")
          assert(gear.level==3 and gear.enabled==false and player.force.research_progress==.5)
        ''')

    def test_settings_follow_the_authored_compact_field_value_grid(self):
        # Original8a settings_rows521-569 keeps provenance in the tooltip,
        # adds defaults only for changed values and marks imported overrides.
        self.lua.execute('''
          boot()
          settings.startup["ips-cost-growth-research_gears"]={value=1.25}
          local root=library.open(player,{tab="settings",settings_scope="research",settings_search="research_gears"})
          local detail=root.mir_library_tabs.mir_library_settings_content.mir_library_settings_dynamic.mir_library_settings_detail
          local page=root.mir_library_tabs.mir_library_settings_content
          local live={}
          for _,child in ipairs(page._children) do if child.valid then live[#live+1]=child end end
          assert(live[1]==page.mir_library_settings_search_label and live[2]==page.mir_library_settings_query
            and live[3]==page.mir_library_settings_toolbar,
            "the original labelled full-width search belongs above the scope buttons")
          assert(page.mir_library_settings_query.style.maximal_width==page.style.maximal_width-24)
          local fields=detail.mir_library_settings_fields
          assert(fields and fields.type=="table" and fields.column_count==2,
            "Settings must use the original compact field/value grid")
          assert(fields.style.horizontal_spacing==12 and fields.style.vertical_spacing==10)
          local growth=fields.mir_library_setting_4_value
          assert(growth.caption[1]=="mir-browser.setting-with-default" and growth.caption[2]=="1.25")
          assert(growth.tooltip[1]=="mir-browser.setting-provenance" and growth.tooltip[2]=="1.25")
          assert(fields.mir_library_setting_4_source==nil,
            "ordinary fields must not repeat the full provenance as another paragraph")
          assert(detail.mir_library_settings_title.style.font=="default-large-bold")
          assert(detail.mir_library_settings_source_summary.caption[1]=="mir-browser.source-direct")
          assert(settings.startup["ips-cost-growth-research_gears"].value==1.25)
          assert(gear.level==3 and gear.enabled==false and player.force.research_progress==.5)
        ''')

    def test_unchanged_details_retain_widgets_snapshot_translation_tab_and_cold_load(self):
        self.lua.execute('''
          boot()
          gear.prototype.effects={{type="change-recipe-productivity",recipe="gears",change=.1}}
          gear.research_unit_ingredients={{name="red",amount=1}}
          player.force.recipes={gears={valid=true,localised_name="Gears"}}
          player.force.valid,gear.force=true,player.force
          player.surface={valid=true,index=1,name="nauvis"}
          defines={flow_precision_index={one_minute=1}}
          local reads=0
          player.force.get_item_production_statistics=function()
            reads=reads+1
            return {valid=true,get_flow_count=function() return 8 end}
          end
          local root=library.open(player,{selected=gear.name})
          local outer=research_content(root).mir_library_detail
          local facts,recipes=outer.mir_library_research_facts,outer.mir_library_recipe_list
          recipes.selected_index=1
          library.on_gui_click({player_index=1,element=facts.mir_library_production_check})
          local snapshot=facts.mir_library_production_results.mir_library_production_snapshot
          assert(snapshot and reads==1)
          local function retained()
            assert(research_content(root).mir_library_detail==outer)
            assert(outer.mir_library_research_facts==facts and facts.valid,
              "an unchanged refresh destroyed the facts scroll widget")
            assert(outer.mir_library_recipe_list==recipes and recipes.valid and recipes.selected_index==1,
              "an unchanged refresh destroyed recipe interaction state")
            assert(facts.mir_library_production_results.mir_library_production_snapshot==snapshot and reads==1,
              "an unchanged refresh discarded or resampled the explicit production snapshot")
          end
          library.open(player);retained()
          library.on_native_state_changed({force=player.force});library.on_native_refresh_tick();retained()
          local request=player.translation_requests[1]
          library.on_string_translated({player_index=1,id=request.id,translated=true,result=gear.localised_name})
          retained()
          local tabs=root.mir_library_tabs
          tabs.selected_tab_index=2;library.on_gui_selected_tab_changed({player_index=1,element=tabs})
          tabs.selected_tab_index=1;library.on_gui_selected_tab_changed({player_index=1,element=tabs});retained()
          -- A fresh module sees the same saved GUI and plain persisted inputs,
          -- without retaining any module-local presentation cache.
          storage=copy_gui_tags(storage)
          package.loaded["runtime.library"]=nil
          library=require("runtime.library")
          local live_game=game;game=nil;library.on_load();game=live_game
          library.open(player);retained()
          assert(gear.level==3 and not gear.enabled and player.force.research_progress==.5)
        ''')

    def test_retained_details_refresh_changed_native_facts_names_scope_and_geometry(self):
        self.lua.execute('''
          boot()
          library_declarations={{id=gear.name,name=gear.name,family="mir",cap=2,cap_setting="cap"}}
          player.force.recipes={gears={valid=true,localised_name="Gears"}}
          player.force.technologies.automation={valid=true,localised_name="Automation"}
          prototypes={item={red={valid=true,localised_name="Red science"}}}
          local detail={effects={{type="change-recipe-productivity",recipe="gears",change=.1}},
            recipe_targets={"gears"},cost={count=100,time=30,ingredients={{name="red",amount=1}}},
            prerequisites={"automation"},recipe_benefits_state="available",
            recipe_benefits={{current_productivity_bonus=.1,maximum_productivity=3}},
            next_level_has_effective_benefit=true,recipe_benefits_only_effects=true}
          require("presentation.library_model").detail=function() return detail end
          local root=library.open(player,{selected=gear.name})
          local function facts() return research_content(root).mir_library_detail.mir_library_research_facts end
          local function changed(mutate,check)
            local previous=facts()
            previous.mir_library_production_results.add{type="label",name="old_snapshot",caption="old"}
            mutate();library.open(player)
            assert(facts()~=previous and not previous.valid,"changed selected facts were retained")
            assert(facts().mir_library_production_results.old_snapshot==nil,"changed facts retained an old snapshot")
            if check then check(facts()) end
            local current=facts();library.open(player)
            assert(facts()==current,"freshly rendered unchanged facts must now be retained")
          end
          changed(function() gear.level=4 end,function(f) assert(f.mir_library_detail_level.caption[2]==4) end)
          changed(function() library_declarations[1].cap=7 end,function(f) assert(f.mir_library_detail_cap.caption[2]==7) end)
          changed(function() detail.cost.count=250 end,function(f) assert(f.mir_library_detail_cost.caption[2]=="250") end)
          changed(function() detail.effects[1].change=.2 end,function(f) assert(f.mir_library_effect_1.caption[2]=="20") end)
          changed(function() detail.recipe_benefits[1].current_productivity_bonus=.4 end,
            function(f) assert(f.mir_library_productivity_current_cap.caption[2]=="40") end)
          changed(function() gear.localised_name="New native name" end,
            function(f) assert(f.mir_library_detail_heading.mir_library_detail_title.caption=="New native name") end)
          changed(function() prototypes.item.red.localised_name="New science" end,
            function(f) assert(f.mir_library_science_icons.mir_library_science_1.tooltip[2]=="New science") end)
          changed(function() player.force.technologies.automation.localised_name="New prerequisite" end,
            function(f) assert(f.mir_library_prerequisite_icons.mir_library_prerequisite_1.tooltip=="New prerequisite") end)
          changed(function() player.force.recipes.gears.localised_name="New recipe" end,
            function() assert(research_content(root).mir_library_detail.mir_library_recipe_list.items[1][3]=="New recipe") end)
          changed(function() player.open_factoriopedia_gui=function() end end,
            function() assert(research_content(root).mir_library_detail.mir_library_recipe_list.tooltip[1]=="mir-browser.recipe-select-hint") end)
          changed(function() player.force.current_research=nil;player.force.research_queue={} end,
            function(f) assert(f.mir_library_detail_context.mir_library_context_current==nil) end)
          changed(function() player.locale="de" end)
          changed(function() player.force.index=2 end)
          changed(function() storage.mir_library.players[1].geometry={width=704,height=604} end)
          changed(function() player.force.recipes.gears.valid=false;gear.localised_description="Visible description" end,
            function(f) assert(f.mir_library_detail_description.caption=="Visible description") end)
          changed(function() gear.localised_description="Changed description" end,
            function(f) assert(f.mir_library_detail_description.caption=="Changed description") end)
        ''')

    def test_detail_retention_declines_unsupported_or_overbudget_inputs_and_repairs_missing_children(self):
        self.lua.execute('''
          boot()
          local detail={effects={},cost={count=100,time=30,ingredients={}}}
          require("presentation.library_model").detail=function() return detail end
          local root=library.open(player,{selected=gear.name})
          local outer=research_content(root).mir_library_detail
          local function facts() return outer.mir_library_research_facts end
          local function rebuilt()
            local previous=facts();library.open(player)
            assert(facts()~=previous and not previous.valid,"unsafe/incomplete presentation stamp was reused")
          end
          outer.tags={};rebuilt()
          local stable=facts();library.open(player);assert(facts()==stable)
          facts().mir_library_detail_heading.destroy();rebuilt()
          gear.localised_description=string.rep("x",65537);rebuilt();rebuilt()
          gear.localised_description=nil
          detail.cost.extra=function() end;rebuilt();rebuilt()
          detail.cost.extra={[2]="sparse"};rebuilt();rebuilt()
          detail.cost.extra=detail.cost;rebuilt();rebuilt()
          detail.cost.extra={};for index=1,4096 do detail.cost.extra[index]=index end;rebuilt();rebuilt()
          detail.cost.extra=0/0;rebuilt();rebuilt()
          detail.cost.extra=nil;rebuilt()
          stable=facts();library.open(player);assert(facts()==stable)
        ''')

    def test_authored_research_presentation_uses_compact_facts_and_independent_recipes(self):
        # 8a3b190d:research_browser.lua729-805: horizontal 48px heading,
        # no generic recipe paragraph, science/prerequisite icons, separate list.
        self.lua.execute('''
          boot()
          gear.localised_description="generic productivity paragraph must remain in its tooltip"
          player.force.recipes={gears={valid=true,localised_name="Gears"}}
          player.force.technologies.automation={valid=true,localised_name="Automation"}
          prototypes={item={red={valid=true,localised_name="Red science"},green={valid=true,localised_name="Green science"}}}
          require("presentation.library_model").detail=function()
            return {effects={{type="change-recipe-productivity",recipe="gears",change=.1}},
              recipe_targets={"gears"},cost={count=100,time=30,ingredients={{name="red",amount=1},{name="green",amount=2}}},
              prerequisites={"automation"}}
          end
          local root=library.open(player,{selected=gear.name})
          local outer=research_content(root).mir_library_detail
          local facts=outer.mir_library_research_facts
          assert(facts and facts.type=="scroll-pane" and facts.vertical_scroll_policy=="auto")
          local heading=facts.mir_library_detail_heading
          assert(heading.direction=="horizontal" and heading.mir_library_detail_icon.style.maximal_width==48)
          assert(heading.mir_library_detail_title.caption==gear.localised_name)
          assert(facts.mir_library_detail_description==nil and facts.mir_library_detail_family==nil,
            "recipe benefits must not repeat their generic description and selected research name")
          assert(facts.mir_library_detail_context.mir_library_context_queue_guidance==nil)
          local divider=facts.mir_library_detail_benefits_divider
          assert(divider.type=="line" and divider.direction=="horizontal")
          assert(divider.style.top_margin==10 and divider.style.bottom_margin==4
            and facts.mir_library_detail_benefits.style.bottom_margin==4,
            "sections must retain the original native dividers and spacing")
          local science=facts.mir_library_science_icons
          assert(science.type=="table" and science.column_count>=2)
          assert(science.mir_library_science_1.sprite=="item/red" and science.mir_library_science_2.sprite=="item/green")
          assert(facts.mir_library_prerequisite_icons.mir_library_prerequisite_1.sprite=="technology/automation")
          assert(outer.mir_library_recipe_list.parent==outer and facts.mir_library_recipe_list==nil)
          assert(outer.mir_library_recipe_list.style.maximal_height==36,
            "one affected recipe uses one row, as in the authored interface")
          assert(facts.style.maximal_height+36+70<=outer.style.maximal_height)
          local sizes=require("presentation.library_layout").split_sizes(480,300)
          assert(sizes.columns==2,"the original400px pane boundary must not stack an adequate split window")
          assert(gear.level==3 and gear.enabled==false and player.force.research_progress==.5)
        ''')

    def test_settings_actions_and_stacked_details_fit_the_page_or_its_vertical_scroll(self):
        self.lua.execute('''
          for _,width in ipairs{480,528,592,832} do
            helpers={write_file=function() error("layout refresh must not write an export") end}
            boot()
            library.open(player,{tab="settings",settings_scope="research"})
            storage.mir_library.players[1].geometry={width=width,height=360}
            local root=library.open(player,{tab="settings"})
            local page=root.mir_library_tabs.mir_library_settings_content
            local toolbar=page.mir_library_settings_toolbar
            local columns=page.style.maximal_width<700 and 2 or 4
            assert(toolbar.type=="table" and toolbar.column_count==columns,
              "Settings actions must wrap before a narrow page clips the fourth export button")
            local names={"settings_research","settings_options","export_settings","export_compact"}
            for _,name in ipairs(names) do
              local button=toolbar["mir_library_"..name]
              assert(button and button.parent==toolbar and button.style.maximal_width>0)
              assert(columns*button.style.maximal_width+(columns-1)*8<=page.style.maximal_width-24,
                "every action must remain inside the page including scrollbar space")
            end
            local dynamic=page.mir_library_settings_dynamic
            local list,detail=dynamic.mir_library_settings_list,dynamic.mir_library_settings_detail
            if dynamic.column_count==1 then
              assert(dynamic.style.minimal_height>=list.style.minimal_height+detail.style.minimal_height+48,
                "the containing table must contain both stacked panes and their headers")
              assert(page.vertical_scroll_policy=="auto" and page.horizontal_scroll_policy=="never")
            end
            for _,label in ipairs{detail.mir_library_settings_title,
              detail.mir_library_settings_fields.mir_library_setting_1_name,detail.mir_library_settings_fields.mir_library_setting_1_value} do
              assert(label.style.single_line==false and label.style.maximal_width<=detail.style.maximal_width-16,
                "localized names and provenance must wrap within the details viewport")
            end
            local selected=storage.mir_library.players[1].setting_selected
            library.on_gui_click({player_index=1,element=toolbar.mir_library_settings_options})
            assert(storage.mir_library.players[1].settings_scope=="options")
            -- Crossing just the toolbar breakpoint must keep it first,
            -- rather than appending the recreated actions below the panes.
            storage.mir_library.players[1].geometry={width=width==832 and 704 or 832,height=360}
            root=library.open(player,{tab="settings"})
            page=root.mir_library_tabs.mir_library_settings_content
            local live={}
            for _,child in ipairs(page._children) do if child.valid then live[#live+1]=child end end
            assert(live[1]==page.mir_library_settings_search_label and live[2]==page.mir_library_settings_query
              and live[3]==page.mir_library_settings_toolbar)
            assert(storage.mir_library.players[1].settings_scope=="options")
            assert(gear.level==3 and gear.enabled==false and player.force.research_progress==.5)
          end
        ''')

    def test_long_imported_profile_is_bounded_in_settings_without_changing_exact_values(self):
        profile = {"schema": 1, "kind": "mir-settings-profile", "metadata": {"note": "ä" * 512},
                   "settings": {"ips-cost-base-research_gears": 777}}
        imported = json.dumps(profile, ensure_ascii=False, separators=(",", ":"))
        # Put the historical 117-byte preview boundary inside a UTF-8 pair.
        if imported.encode("utf-8")[116] != 0xC3:
            profile["metadata"]["note"] = "x" + profile["metadata"]["note"]
            imported = json.dumps(profile, ensure_ascii=False, separators=(",", ":"))
        self.lua.globals().imported_profile_json = imported
        self.lua.globals().parse_profile_json = lambda text: self.lua.table_from(json.loads(text), recursive=True)
        self.lua.globals().valid_preview_utf8 = lambda text: isinstance(text, str) and text.endswith("...")
        self.lua.execute('''
          boot()
          local imported=imported_profile_json
          helpers={encode_string=function(value) return value end,
            decode_string=function() error("raw JSON imports must not use the encoded string decoder") end,
            json_to_table=parse_profile_json}
          assert(require("research.settings_profile").decode(imported,helpers)
            .settings["ips-cost-base-research_gears"]==777,"profile fixture must be accepted before display")
          settings.startup["mir-settings-profile-import"]={value=imported}
          settings.startup["ips-cost-base-research_gears"]={value=4242}
          local root=library.open(player,{tab="settings",settings_scope="options",settings_search="mir-settings-profile-import"})
          local detail=root.mir_library_tabs.mir_library_settings_content
            .mir_library_settings_dynamic.mir_library_settings_detail
          local shown=detail.mir_library_settings_fields.mir_library_setting_1_value.caption[2]
          assert(type(shown)=="string" and #shown<=120 and shown:sub(-3)=="...",
            "opaque imported profiles must not flood the ordinary Settings view")
          assert(shown:sub(1,8)==imported:sub(1,8) and valid_preview_utf8(shown))
          local source=detail.mir_library_settings_fields.mir_library_setting_1_value.tooltip
          assert(type(source[2])=="string" and #source[2]<=120)
          assert(settings.startup["mir-settings-profile-import"].value==imported)
          assert(settings.startup["ips-cost-base-research_gears"].value==4242)
          assert(require("research.settings").effective_values(settings.startup,helpers)
            ["ips-cost-base-research_gears"]==777,"display shortening changed imported effective settings")
          assert(gear.level==3 and gear.enabled==false and player.force.research_progress==.5)
        ''')

    def test_returning_from_availability_removes_its_projection_before_research(self):
        self.lua.execute('''
          for _,width in ipairs{592,528} do
          for _,empty in ipairs{false,true} do
            boot()
            require("presentation.availability").rows=function()
              return empty and {} or {{family="research_gears",reason="requires-space-age"}}
            end
            library.open(player)
            storage.mir_library.players[1].geometry={width=width,height=480}
            local root=library.open(player,{tab="research",visibility=3})
            local body=research_content(root)
            local name=empty and "mir_library_availability_empty" or "mir_library_availability_1"
            local old=body[name]
            assert(old and old.valid)
            local visibility=research_filters(root)["mir_library_filter_grid"]["mir_library_visibility_field"]["mir_library_visibility"]
            visibility.selected_index=1
            library.on_gui_selection_state_changed({player_index=1,element=visibility})
            assert(not old.valid and body[name]==nil,
              "Availability labels must not survive into the ordinary Research grid")
            assert(body.mir_library_list_pane.mir_library_results.valid and body.mir_library_detail.valid)
            -- Repair a retained body produced by the intermediate mixed-layout draft.
            local orphan=body.add{type="label",name="mir_library_availability_1",caption="old projection"}
            library.open(player)
            assert(not orphan.valid and body.mir_library_availability_1==nil)
            assert(body.mir_library_list_pane.mir_library_results.valid and body.mir_library_detail.valid)
          end
          end
        ''')

    def test_explicit_resize_does_not_read_the_clicked_element_after_layout_rebuild(self):
        self.lua.execute('''
          boot()
          local root=library.open(player,{selected=gear.name,search="gear"})
          local view=storage.mir_library.players[1]
          view.geometry={width=592,height=480}
          root=library.open(player)
          root.location={x=31,y=17}
          library.on_gui_location_changed({player_index=1,element=root})
          assert(research_content(root).type=="table")
          for _,action in ipairs{"layout_smaller","layout_larger","layout_smaller","layout_reset"} do
            local old=root
            player.display_resolution={width=action=="layout_smaller" and 480 or 1280,height=720}
            local button=root.mir_library_title["mir_library_"..action]
            local name=button.name
            rawset(button,"name",nil)
            local meta=getmetatable(button)
            local original_index=meta.__index
            meta.__index=function(target,key)
              if key=="name" then
                local ancestor=target
                while ancestor do
                  assert(ancestor.valid,"LuaGuiElement API call when LuaGuiElement invalid")
                  ancestor=ancestor._parent
                end
                return name
              end
              return original_index(target,key)
            end
            library.on_gui_click({player_index=1,element=button})
            root=player.gui.screen.mir_research_browser
            view=storage.mir_library.players[1]
            assert(root and root.valid and root~=old and not old.valid,
              "crossing the split/stacked boundary must replace the obsolete layout safely")
            assert(research_filters(root).mir_library_query.text=="gear" and view.selected==gear.name)
          end
          assert(view.geometry==nil and view.location==nil)
          assert(root.force_auto_center_calls>=1)
          assert(gear.level==3 and gear.enabled==false and player.force.research_progress==.5)
        ''')

    def test_research_refresh_retains_list_controls_without_repositioning_unchanged_items(self):
        self.lua.execute('''
          boot()
          local root=library.open(player,{selected=gear.name})
          local body=research_content(root)
          local list,actions=body.mir_library_list_pane.mir_library_results,body.mir_library_list_pane.mir_library_actions
          local detail=body.mir_library_detail
          local scroll_calls=0
          list.scroll_to_item=function() scroll_calls=scroll_calls+1 end
          local items,writes=list.items,0
          rawset(list,"items",nil)
          local meta=getmetatable(list)
          local previous_index,previous_write=meta.__index,meta.__newindex
          meta.__index=function(target,key)
            if key=="items" then return items end
            return previous_index(target,key)
          end
          meta.__newindex=function(target,key,value)
            if key=="items" then writes=writes+1;items=value else previous_write(target,key,value) end
          end
          library.open(player)
          assert(body.mir_library_list_pane.mir_library_results==list and list.valid and body.mir_library_list_pane.mir_library_actions==actions,
            "ordinary refresh must retain the native list and its interaction context")
          assert(body.mir_library_detail==detail and detail.valid)
          library.open(player,{tab="queue"})
          library.open(player,{tab="research"})
          assert(research_content(root).mir_library_list_pane.mir_library_results==list and list.valid)
          assert(scroll_calls==0,"unchanged lists must not be programmatically scrolled again")
          assert(writes==0,"unchanged native items must not be reassigned")
          local model=require("presentation.library_model")
          local original=model.rows
          model.rows=function(...)
            local rows=original(...);rows[1].name="Updated display name";return rows
          end
          library.open(player)
          assert(body.mir_library_list_pane.mir_library_results==list and writes==1 and list.items[1][3]=="Updated display name",
            "changed display names must update the retained native list")
          assert(gear.level==3 and gear.enabled==false and player.force.research_progress==.5)
        ''')

    def test_filter_excluding_selection_selects_the_first_matching_subject(self):
        self.lua.execute('''
          boot()
          local root=library.open(player,{family="all",selected=foreign.name})
          local list=research_content(root).mir_library_list_pane.mir_library_results
          local query=research_filters(root).mir_library_query
          query.text="gear"
          library.on_gui_text_changed({player_index=1,element=query})
          local body=research_content(root)
          assert(#list.items==1 and list.selected_index==1
            and storage.mir_library.players[1].selected==gear.name,
            "an excluded old selection must not leave a nonempty result list without details")
          assert(body.mir_library_list_pane.mir_library_results==list and list.valid)
          assert(body.mir_library_detail.mir_library_research_facts.mir_library_detail_heading.mir_library_detail_title.caption==gear.localised_name)
          assert(gear.level==3 and foreign.level==1 and player.force.research_progress==.5)
        ''')

    def test_settings_refresh_retains_its_list_and_search_context(self):
        self.lua.execute('''
          boot()
          local root=library.open(player,{tab="settings",settings_search="research_gears"})
          local content=root.mir_library_tabs.mir_library_settings_content
          local dynamic=content.mir_library_settings_dynamic
          local list,detail=dynamic.mir_library_settings_list,dynamic.mir_library_settings_detail
          local query=content.mir_library_settings_query
          local scroll_calls=0
          list.scroll_to_item=function() scroll_calls=scroll_calls+1 end
          library.open(player,{tab="settings"})
          library.on_gui_selection_state_changed({player_index=1,element=list})
          assert(dynamic.mir_library_settings_list==list and list.valid,
            "Settings selection must retain the native list")
          assert(dynamic.mir_library_settings_detail==detail and detail.valid)
          assert(content.mir_library_settings_query==query and query.text=="research_gears")
          assert(scroll_calls==0,"unchanged Settings lists must not be scrolled on refresh")
          assert(gear.level==3 and gear.enabled==false and player.force.research_progress==.5)
        ''')

    def test_settings_use_authored_short_field_names_and_honest_compact_numbers(self):
        self.lua.execute('''
          boot()
          settings.startup["ips-cost-growth-research_gears"]={value=1.23456789}
          local root=library.open(player,{tab="settings",settings_scope="research",settings_search="research_gears"})
          local detail=root.mir_library_tabs.mir_library_settings_content
            .mir_library_settings_dynamic.mir_library_settings_detail
          local keys={"enable","cost-base","cost-linear-increment","cost-growth","max-level","research-time","effect-per-level-percent"}
          for index,key in ipairs(keys) do
            assert(detail.mir_library_settings_fields["mir_library_setting_"..index.."_name"].caption[1]=="mir-browser.setting-"..key,
              "the group already names the research; standard field names must stay short")
          end
          local growth=detail.mir_library_settings_fields.mir_library_setting_4_value
          assert(growth.caption[1]=="mir-browser.setting-with-default" and growth.caption[2]=="≈ 1.23457","rounded display must be compact and visibly approximate")
          assert(growth.tooltip[2]=="≈ 1.23457" and growth.tooltip[4][1]=="mir-browser.source-direct")
          assert(detail.mir_library_settings_fields.mir_library_setting_5_value.caption[1]=="mir-browser.setting-unlimited")
          assert(settings.startup["ips-cost-growth-research_gears"].value==1.23456789,
            "presentation must not round configuration or profile values")
          assert(gear.level==3 and gear.enabled==false and player.force.research_progress==.5)
        ''')

    def test_effect_field_labels_keep_the_original_percentage_and_native_units(self):
        # Published4.7.3 direct-effects.lua plus descriptor.lua give exactly
        # these four native-unit stream contracts; productivity uses percent.
        # Its renderer keeps native-continuation labels generic.
        self.lua.execute('''
          boot()
          local catalog=require("research.settings")
          local native_units={research_inventory_capacity=true,research_character_reach=true,
            research_cargo_bay_unloading_distance=true,research_cargo_landing_pad_count=true}
          local checked,continuations,native=0,0,0
          library.open(player,{tab="settings",settings_scope="research",settings_search=""})
          for _,name in ipairs(catalog.registered_names()) do
            local spec=catalog.spec(name)
            if spec.key=="effect_percent" and spec.stream then
              local stream=spec.stream
              local percent=not stream.native_continuation and not native_units[stream.key]
              if not stream.native_continuation then
                assert((spec.type=="int-setting")== (native_units[stream.key]==true),
                  "the compact caption needs review when an authored unit changes: "..stream.key)
              end
              storage.mir_library.players[1].setting_selected=stream.key
              local root=library.open(player,{tab="settings"})
              local content=root.mir_library_tabs.mir_library_settings_content
              assert(storage.mir_library.players[1].setting_selected==stream.key)
              local field=content.mir_library_settings_dynamic.mir_library_settings_detail
                .mir_library_settings_fields.mir_library_setting_7_name
              assert(field.caption[1]=="mir-browser.setting-effect-per-level"..(percent and "-percent" or ""),
                "the seventh field repeats its title or misstates its units: "..stream.key)
              checked=checked+1
              if stream.native_continuation then continuations=continuations+1 end
              if native_units[stream.key] then native=native+1 end
            end
          end
          assert(checked>70 and continuations>0 and native==4)
          assert(gear.level==3 and gear.enabled==false and player.force.research_progress==.5)
        ''')

    def test_research_details_present_localized_benefits_before_requirements(self):
        self.lua.execute('''
          boot()
          gear.localised_description={"technology-description.research-speed"}
          local scripted={"modifier-description.more-infinite-research.agricultural_growth_speed","10"}
          local model=require("presentation.library_model")
          model.detail=function()
            return {effects_complete=true,effects={
              {type="laboratory-speed",modifier=.6},
              {type="worker-robot-storage",modifier=1},
              {type="nothing",effect_description=scripted},
              {type="change-recipe-productivity",recipe="gears",change=.1},
              {type="change-recipe-productivity",recipe="iron",change=.1}},
              cost={count=100,time=30,ingredients={{name="automation-science-pack",amount=1}}}}
          end
          local root=library.open(player,{selected=gear.name})
          local detail=research_content(root).mir_library_detail
          local position={}
          for index,child in ipairs(detail.mir_library_research_facts._children) do position[child.name]=index end
          assert(detail.mir_library_research_facts.mir_library_detail_benefits and detail.mir_library_research_facts.mir_library_detail_requirements,
            "Benefit and Research requirements must be clear sections")
          assert(position.mir_library_detail_benefits < position.mir_library_effect_1
            and position.mir_library_effect_1 < position.mir_library_detail_requirements
            and position.mir_library_detail_requirements < position.mir_library_detail_cost,
            "show what research improves before its requirements")
          assert(detail.mir_library_research_facts.mir_library_detail_description.caption==gear.localised_description)
          assert(detail.mir_library_research_facts.mir_library_detail_heading.mir_library_detail_icon.style.minimal_width==48
            and detail.mir_library_research_facts.mir_library_detail_heading.mir_library_detail_icon.style.minimal_height==48)
          assert(detail.mir_library_research_facts.mir_library_detail_heading.mir_library_detail_icon.resize_to_sprite==false
            and detail.mir_library_research_facts.mir_library_detail_heading.mir_library_detail_icon.style.stretch_image_to_widget_size==true,
            "the actual sprite must fit the box, not overlap the adjacent facts at native size")
          local speed=detail.mir_library_research_facts.mir_library_effect_1.caption
          assert(speed[2][1]=="gui-bonus.laboratory-speed" and speed[4]=="+60%")
          assert(detail.mir_library_research_facts.mir_library_effect_2.caption[4]=="+1")
          assert(detail.mir_library_research_facts.mir_library_effect_3.caption==scripted)
          assert(detail.mir_library_research_facts.mir_library_effect_4.caption[1]=="mir-browser.productivity-increment"
            and detail.mir_library_research_facts.mir_library_effect_5==nil,"identical per-recipe gains repeat the same fact")
          assert(gear.level==3 and gear.enabled==false and player.force.research_progress==.5)
        ''')

    def test_unsupported_effects_link_to_native_facts_without_raw_type_or_invented_numbers(self):
        self.lua.execute('''
          boot()
          local model=require("presentation.library_model")
          model.detail=function() return {effects={{type="future-foreign-effect",modifier=12345}}} end
          local root=library.open(player,{selected=gear.name})
          local detail=research_content(root).mir_library_detail
          assert(detail.mir_library_research_facts.mir_library_effect_1==nil)
          assert(detail.mir_library_research_facts.mir_library_other_effects.caption[1]=="mir-browser.effect-native-details")
          assert(research_content(root).mir_library_list_pane.mir_library_actions.mir_library_open_native.enabled)
          assert(gear.level==3 and gear.enabled==false)
        ''')

    def test_discovery_queue_uses_anonymous_labels_without_changing_native_entries(self):
        self.lua.execute('''
          boot()
          script={active_mods={base="2.1.23",discovery_tree="1.0.12"}}
          package.preload["presentation.library_model"]=nil
          package.loaded["presentation.library_model"],package.loaded["runtime.library"]=nil,nil
          library=require("runtime.library")
          local root=library.open(player,{tab="queue"})
          local list=root["mir_library_tabs"]["mir_library_queue_content"]["mir_library_queue_list"]
          assert(list.items[1][3][1]=="mir-browser.undiscovered-research")
          assert(player.force.research_queue[1]==gear and player.force.current_research==gear
            and player.force.research_progress==.5 and gear.enabled==false)
          gear.enabled=true -- fresh upstream discovery observation
          library.open(player,{tab="queue"})
          list=root["mir_library_tabs"]["mir_library_queue_content"]["mir_library_queue_list"]
          assert(list.items[1][3]==gear.localised_name)
        ''')

    def test_settings_explain_a_foreign_continuation_without_claiming_its_controls(self):
        self.lua.execute('''
          boot()
          local runtime_catalogue=require("runtime.catalogue")
          runtime_catalogue.externally_supplied_continuation=function(id) return id=="braking-force-8" end
          local root=library.open(player,{tab="settings",settings_scope="research",settings_search="braking-force"})
          local detail=root["mir_library_tabs"]["mir_library_settings_content"]
            ["mir_library_settings_dynamic"]["mir_library_settings_detail"]
          assert(detail["mir_library_settings_external"].caption[1]=="mir-browser.settings-external-owner")
          assert(detail["mir_library_settings_external"].style.single_line==false)
        ''')

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""

          package.preload["research.catalogue"] = function()
            return {
              gear_id = function() return "recipe-prod-research_gears-1" end,
              internal_credit_ids = function() return library_private_credit_ids or {} end,
              declared = function()
                return library_declarations or {
                  {id = "recipe-prod-research_gears-1", name = "Iron gear wheel productivity",
                    family = "mir", cap = 2, cap_setting = "ips-max-level-research_gears",
                    finite = false, max_level = "infinite"}
                }
              end
            }
          end

          package.preload["presentation.library_model"] = function()
            local function copy(row, technology, queued_count, queue_index, current, display_name)
              local result = {
                id = row.id, name = display_name or row.name, family = row.family, finite = row.finite,
                max_level = row.max_level, cap = row.cap, cap_setting = row.cap_setting,
                cap_state = row.cap and "finite" or "unlimited",
                current_level = technology and technology.level or 1,
                researched = technology and technology.researched or false,
                enabled = technology and technology.enabled or false,
                visible = technology and technology.visible_when_disabled or false,
                queued_count = queued_count, queue_index = queue_index, current = current,
                prerequisites = {}
              }
              if current or queued_count > 0 then result.status = "queued"
              elseif result.enabled then result.status = "ready"
              else result.status = "locked" end
              return result
            end
            local function queue_facts(force, id)
              local count, first = 0, nil
              for index, queued in ipairs(force.research_queue or {}) do
                local name = type(queued) == "table" and queued.name or queued
                if name == id then
                  count = count + 1
                  if first == nil then first = index end
                end
              end
              local current = force.current_research
              local current_name = type(current) == "table" and current.name or current
              return count, first, current_name == id
            end
            return {
              normalize = function(view)
                local mode = type(view.mode) == "number" and view.mode or 1
                if mode < 1 or mode > 3 or mode ~= math.floor(mode) then mode = 1 end
                local status = type(view.status) == "number" and view.status or 1
                if status < 1 or status > 4 or status ~= math.floor(status) then status = 1 end
                local page = type(view.page) == "number" and view.page or 1
                if page < 1 or page > 30000 or page ~= math.floor(page) then page = 1 end
                local sort = view.sort
                if sort ~= "progression" and sort ~= "native" and sort ~= "name-asc" and sort ~= "name-desc" then
                  sort = "progression"
                end
                local stable_sort = view.stable_sort
                if stable_sort ~= "progression" and stable_sort ~= "native" then stable_sort = "progression" end
                local visibility = type(view.visibility) == "number" and view.visibility or 1
                if visibility < 1 or visibility > 3 or visibility ~= math.floor(visibility) then visibility = 1 end
                local hidden = {}
                if type(view.hidden) == "table" then
                  for id, hidden_value in pairs(view.hidden) do
                    if hidden_value == true and type(id) == "string" then hidden[id] = true end
                  end
                end
                return {
                  query = type(view.search) == "string" and view.search or (type(view.query) == "string" and view.query or ""),
                  family = view.family == "mir" and "mir" or "all",
                  mode = mode,
                  status = status,
                  page = page,
                  sort = sort,
                  stable_sort = stable_sort,
                  visibility = visibility,
                  hidden = hidden,
                  selected = type(view.selected) == "string" and view.selected or nil
                }
              end,
              rows = function(force, rows, view, translations)
                assert(type(translations) == "table")
                local output = {}
                for _, row in ipairs(rows) do
                  local technology = force.technologies[row.id]
                  local display_name = translations[row.id] or row.name
                  local name = string.lower(display_name)
                  local query = string.lower(view.query or view.search or "")
                  local queued_count, queue_index, current = queue_facts(force, row.id)
                  local copied = copy(row, technology, queued_count, queue_index, current, display_name)
                  if (view.family == "all" or row.family == view.family)
                    and (query == "" or string.find(name, query, 1, true))
                    and (view.status == 1
                      or (view.status == 2 and copied.status == "ready")
                      or (view.status == 3 and copied.status == "locked")
                      or (view.status == 4 and copied.status == "queued")) then
                    output[#output + 1] = copied
                  end
                end
                return output
              end,
              detail = function(force, rows, view, translations)
                for _, row in ipairs(rows) do
                  if row.id == view.selected then
                    local technology = force.technologies[row.id]
                    local effects, recipe_targets = {}, {}
                    for _, effect in ipairs(technology.prototype.effects or {}) do
                      effects[#effects + 1] = effect
                      if (effect.type == "unlock-recipe" or effect.type == "change-recipe-productivity")
                          and type(effect.recipe) == "string" then
                        recipe_targets[#recipe_targets + 1] = effect.recipe
                      end
                    end
                    return {cost = {count = 8000, time = 60,
                        ingredients = technology.research_unit_ingredients or {}},
                      prerequisites = {}, effects = effects, recipe_targets = recipe_targets}
                  end
                end
                return nil
              end
            }
          end

          function gui_style()
            local values = {}
            local function assert_int32(key, value)
              assert(type(value) == "number" and value == math.floor(value)
                and value >= -2147483648 and value <= 2147483647,
                "LuaStyle." .. key .. " requires an int32")
            end
            return setmetatable({}, {
              __index = function(_, key) return values[key] end,
              __newindex = function(_, key, value)
                if key == "width" then
                  assert_int32(key, value)
                  -- LuaStyle.width writes both bounds. Keep this host double
                  -- aligned with the native F200/F210 GUI contract.
                  values.minimal_width, values.maximal_width = value, value
                elseif key == "height" then
                  assert_int32(key, value)
                  values.minimal_height, values.maximal_height = value, value
                elseif key == "minimal_width" or key == "maximal_width"
                    or key == "minimal_height" or key == "maximal_height" then
                  assert_int32(key, value)
                  values[key] = value
                else
                  values[key] = value
                end
              end
            })
          end

          function copy_gui_tags(value)
            if type(value)~="table" then return value end
            local result={}
            for key,child in pairs(value) do result[key]=copy_gui_tags(child) end
            return result
          end

          function gui_container(parent)
            local value = {valid = true, parent = parent, _parent = parent, _children = {}, style = gui_style()}
            value.auto_center = true
            value.force_auto_center = function()
              assert(value.auto_center == true, "native force_auto_center requires an auto-centering frame")
              value.force_auto_center_calls = (value.force_auto_center_calls or 0) + 1
            end
            value.add = function(spec)
              if spec.type == "text-box" then
                assert(spec.read_only == nil and spec.word_wrap == nil,
                  "native text-box add accepts text/icon_selector; set read_only/word_wrap after creation")
              end
              if spec.type == "tabbed-pane" and spec.name == "mir_library_tabs" then
                assert(spec.selected_tab_index == nil, "MIR must select a tab only after add_tab entries exist")
              end
              local element = gui_container(value)
              for key, field in pairs(spec) do
                if key == "style" then element.style_name = field else element[key] = field end
              end
              local read_only_column_count = element.column_count
              local native_tags = copy_gui_tags(element.tags or {})
              rawset(element, "column_count", nil)
              rawset(element, "tags", nil)
              setmetatable(element, {
                __index = function(_, key)
                  if key == "column_count" then return read_only_column_count end
                  if key == "children" then
                    local children={}
                    for _,child in ipairs(element._children) do if child.valid then children[#children+1]=child end end
                    return children
                  end
                  if key == "tags" then return copy_gui_tags(native_tags) end
                end,
                __newindex = function(target, key, field)
                  if key == "column_count" then error("LuaGuiElement.column_count is read only") end
                  if key == "tags" then native_tags=copy_gui_tags(field);return end
                  rawset(target, key, field)
                end
              })
              value._children[#value._children + 1] = element
              if element.name then value[element.name] = element end
              element.destroy = function()
                if not element.valid then return end
                element.valid = false
                if element.name then element._parent[element.name] = nil end
              end
              element.clear = function()
                for _, child in ipairs(element._children) do
                  child.valid = false
                  if child.name then element[child.name] = nil end
                end
                element._children = {}
              end
              element.scroll_to_item = function(index, mode)
                element.scrolled_to = {index = index, mode = mode}
              end
              element.add_tab = function(tab, content)
                element._tabs = element._tabs or {}
                element._tabs[#element._tabs + 1] = {tab = tab, content = content}
              end
              return element
            end
            return value
          end

          function debug_tools(page)
            return page.mir_library_help_panes.mir_library_help_tools
          end
          function debug_report(page)
            return page.mir_library_help_panes.mir_library_report_panel
          end

          function research_page(root)
            local tabs = root and root["mir_library_tabs"]
            return tabs and tabs["mir_library_research_page"] or nil
          end
          function research_filters(root)
            local page = research_page(root)
            return page and page["mir_library_filters"] or nil
          end
          function research_content(root)
            local page = research_page(root)
            return page and page["mir_library_research_content"] or (root and root["mir_library_content"])
          end

          function boot()
            storage = {}
            settings = {startup = {}}
            library_declarations = nil
            library_private_credit_ids = library_private_credit_ids or {}
            screen = gui_container(nil)
            gear = {valid = true, name = "recipe-prod-research_gears-1", level = 3,
              researched = true, enabled = false, visible_when_disabled = true,
              localised_name = "Iron gear wheel productivity",
              prototype = {max_level = 4294967295}}
            foreign = {valid = true, name = "foreign-research", level = 1,
              researched = false, enabled = true, visible_when_disabled = false,
              localised_name = "Foreign research", prototype = {max_level = 3}}
            player = {valid = true, index = 1, locale = "en", connected = true, gui = {screen = screen},
              display_resolution = {width = 1280, height = 720}, display_scale = 1,
              force = {
                index = 1, technologies = {[gear.name] = gear, [foreign.name] = foreign},
                research_queue = {gear}, current_research = gear, research_progress = .5,
                add_research = function() error("Library must not add native research") end,
                cancel_current_research = function() error("Library must not cancel native research") end
              }}
            player.set_shortcut_toggled = function(name, value)
              player.shortcut_name, player.shortcut_toggled = name, value
            end
            player.open_technology_gui = function(technology)
              player.opened_technology = technology
            end
            player.translation_requests, player.next_translation_id = {}, 0
            player.request_translation = function(localised)
              player.next_translation_id = player.next_translation_id + 1
              local request = {id = player.next_translation_id, localised = localised}
              player.translation_requests[#player.translation_requests + 1] = request
              return request.id
            end
            game = {tick = 0, get_player = function(index) return index == 1 and player or nil end}
            package.loaded["runtime.library"] = nil
            library = require("runtime.library")
          end

          function route_native_events(reload_library, caps_active, extra_events)
            native_handlers, native_ticks = {events={}}, {}
            native_cap_completions = 0
            native_policy_reset_force = nil
            caps_active = caps_active == true
            package.loaded["runtime.lifecycle"] = nil
            package.preload["runtime.lifecycle"] = function()
              return {caps_active=function() return caps_active end,cap_limits=function() return {} end,
                on_init=function() end,on_configuration_changed=function() end,on_load=function() end,
                on_research_finished=function() native_cap_completions=native_cap_completions+1 end,
                on_technology_effects_reset=function(event) native_policy_reset_force=event.force end,
                on_force_created=function() end,on_force_reset=function() end,on_forces_merged=function() end}
            end
            script = {active_mods={base="2.1.23"},
              on_event=function(id,callback) native_handlers.events[id]=callback end,
              on_nth_tick=function(interval,callback) native_ticks[interval]=callback end,
              on_init=function(callback) native_handlers.init=callback end,
              on_load=function(callback) native_handlers.load=callback end,
              on_configuration_changed=function(callback) native_handlers.configuration=callback end}
            defines = {events={on_research_finished=1,on_gui_closed=2,on_research_started=3,
              on_research_cancelled=4,on_research_reversed=5,on_research_queued=6,on_research_moved=7,
              on_technology_effects_reset=8,on_force_reset=9,on_forces_merged=10,
              on_player_left_game=11,on_player_joined_game=12,on_player_changed_force=13}}
            for name,id in pairs(extra_events or {}) do defines.events[name]=id end
            remote = {interfaces={},add_interface=function(name,methods) remote.interfaces[name]=methods end}
            commands = {add_command=function() end}
            if reload_library then
              package.loaded["runtime.library"] = nil
              library = require("runtime.library")
            end
            package.loaded["runtime.bootstrap"] = nil
            require("runtime.bootstrap").register()
          end

          function boot_native_events()
            boot()
            gear.force, foreign.force = player.force, player.force
            route_native_events(false)
          end

          function open_routed(options)
            assert(remote.interfaces["more-infinite-research-browser"].open(1,options) == true)
            return player.gui.screen["mir_research_browser"]
          end

          function queued_rows()
            return #research_content(player.gui.screen["mir_research_browser"])["mir_library_list_pane"]["mir_library_results"].items
          end
        ''')

    def test_native_research_events_refresh_once_after_engine_state_settles_and_unsubscribe_on_close(self):
        self.lua.execute(r'''
          boot_native_events()
          assert(native_handlers.events[1] == nil and native_ticks[1] == nil)
          local model = require("presentation.library_model")
          local original_rows, row_calls = model.rows, 0
          model.rows = function(...)
            row_calls = row_calls + 1
            return original_rows(...)
          end
          local root = open_routed({status=4,selected=gear.name})
          assert(queued_rows() == 1)
          local initial_rows = row_calls
          assert(type(native_handlers.events[1]) == "function", "open Library did not subscribe to native research")
          local query = research_filters(root)["mir_library_query"]
          -- The callback can precede the final native queue transition.
          native_handlers.events[1]({research=gear})
          native_handlers.events[3]({research=gear})
          native_handlers.events[7]({force=player.force})
          assert(queued_rows() == 1 and type(native_ticks[1]) == "function")
          assert(row_calls == initial_rows,
            "research-event bursts must defer catalogue work until the coalesced refresh tick")
          gear.level = 4
          player.force.research_queue, player.force.current_research, player.force.research_progress = {},nil,0
          local queue = player.force.research_queue
          native_ticks[1]({tick=1})
          assert(queued_rows() == 0 and native_ticks[1] == nil)
          assert(row_calls == initial_rows + 1,
            "one coalesced research-event burst must rebuild the catalogue only once")
          assert(player.gui.screen["mir_research_browser"] == root
            and research_filters(root)["mir_library_query"] == query and query.valid)
          assert(player.force.research_queue == queue and player.force.current_research == nil
            and player.force.research_progress == 0 and gear.level == 4)
          native_handlers.events[2]({player_index=1,element=root})
          for _, id in ipairs({1,3,4,5,6,7}) do assert(native_handlers.events[id] == nil) end
          assert(native_ticks[1] == nil and not library.native_subscription_needs()
            and row_calls == initial_rows + 1,
            "closing a settled view must leave no recurring catalogue work")
        ''')

    def test_pending_native_view_refresh_reconstructs_after_cold_load_without_game_or_save_writes(self):
        self.lua.execute(r'''
          boot_native_events()
          open_routed({status=4})
          native_handlers.events[6]({research=gear})
          player.force.research_queue, player.force.current_research, player.force.research_progress = {},nil,0
          local saved, view, available_game = storage, storage.mir_library.players[1], game
          assert(view.open and view.refresh_pending)
          game = nil
          route_native_events(true)
          native_handlers.load()
          assert(storage == saved and storage.mir_library.players[1] == view and view.open and view.refresh_pending)
          assert(type(native_handlers.events[1]) == "function" and type(native_ticks[1]) == "function")
          game = available_game
          native_ticks[1]({tick=1})
          assert(queued_rows() == 0 and native_ticks[1] == nil)
        ''')

    def test_native_events_refresh_the_actual_library_model_and_selected_detail(self):
        self.lua.execute(r'''
          -- Exercise the production query model as well as the actual GUI and
          -- bootstrap; the other controls isolate their GUI boundary with a
          -- small model double.
          package.preload["presentation.library_model"] = nil
          package.loaded["presentation.library_model"] = nil
          boot_native_events()
          local root = open_routed({status=4,selected=gear.name})
          assert(queued_rows() == 1)
          native_handlers.events[1]({research=gear})
          gear.level, gear.researched, gear.enabled = 4,false,true
          player.force.research_queue, player.force.current_research, player.force.research_progress = {},nil,0
          local queue = player.force.research_queue
          native_ticks[1]({tick=1})
          assert(queued_rows() == 0 and native_ticks[1] == nil)
          assert(open_routed({status=1,selected=gear.name}) == root)
          local detail = research_content(root)["mir_library_detail"]
          assert(detail.mir_library_research_facts["mir_library_detail_level"].caption[2] == 4)
          native_handlers.events[5]({research=gear})
          gear.level = 3
          native_ticks[1]({tick=2})
          assert(research_content(root)["mir_library_detail"].mir_library_research_facts["mir_library_detail_level"].caption[2] == 3)
          assert(player.force.research_queue == queue and player.force.current_research == nil
            and player.force.research_progress == 0 and gear.level == 3 and not gear.researched)
        ''')

    def test_closing_a_view_retains_independent_cap_research_callbacks(self):
        self.lua.execute(r'''
          boot_native_events()
          route_native_events(false,true)
          local root = open_routed()
          native_handlers.events[2]({player_index=1,element=root})
          assert(type(native_handlers.events[1]) == "function" and type(native_handlers.events[3]) == "function")
          assert(native_handlers.events[6] == nil and native_handlers.events[7] == nil and native_ticks[1] == nil)
          native_handlers.events[1]({research=gear})
          assert(native_cap_completions == 1 and native_ticks[1] == nil)
        ''')

    def test_queue_reversal_effect_reset_and_force_boundaries_route_live_native_views(self):
        self.lua.execute(r'''
          for _, id in ipairs({4,5,6,7,8,9,10}) do
            boot_native_events()
            open_routed({status=4})
            player.force.research_queue, player.force.current_research, player.force.research_progress = {},nil,0
            native_handlers.events[id]({research=gear,force=player.force,destination=player.force,source_index=2})
            if id == 8 then
              assert(native_policy_reset_force == player.force,
                "open-view effects reset displaced prototype-policy cleanup")
            end
            assert(type(native_ticks[1]) == "function", "native boundary did not schedule view refresh: "..id)
            native_ticks[1]({tick=1})
            assert(queued_rows() == 0 and native_ticks[1] == nil)
          end
        ''')

    def test_force_change_refreshes_an_open_queue_tab_without_a_translation_cache(self):
        self.lua.execute(r'''
          boot_native_events()
          local root = open_routed({tab="queue"})
          local content = root["mir_library_tabs"]["mir_library_queue_content"]
          assert(#content["mir_library_queue_list"].items == 1 and #player.translation_requests == 0)
          player.force = {index=2,technologies={[gear.name]=gear},research_queue={},research_progress=0}
          native_handlers.events[13]({player_index=1})
          assert(player.gui.screen["mir_research_browser"] == root)
          assert(#content["mir_library_queue_list"].items == 0,
            "force change kept the old queue when no translation cache existed")
        ''')

    def test_native_refresh_ignores_other_forces_and_foreign_frames_and_rejoins_live_views(self):
        self.lua.execute(r'''
          boot_native_events()
          local root = open_routed({status=4})
          native_handlers.events[7]({force={index=2}})
          assert(native_ticks[1] == nil)
          player.connected = false
          native_handlers.events[11]({player_index=1})
          assert(native_handlers.events[1] == nil and native_ticks[1] == nil and root.valid)
          player.connected = true
          native_handlers.events[12]({player_index=1})
          assert(storage.mir_library.players[1].open == true
            and type(native_handlers.events[1]) == "function")
          root.destroy()
          local foreign_root = screen.add{type="frame",name="mir_research_browser"}
          native_handlers.events[5]({research=gear})
          assert(foreign_root.valid and screen["mir_research_browser"] == foreign_root)
          assert(native_ticks[1] == nil and native_handlers.events[1] == nil)
          assert(storage.mir_library.translations.working == nil,
            "lost owned frame retained its working cache")
        ''')

    def test_join_without_an_owned_root_retires_open_view_subscriptions_but_keeps_issued_translation_ids(self):
        self.lua.execute(r'''
          boot_native_events()
          local root = open_routed()
          native_handlers.events[1]({research=gear})
          local state, view = storage, storage.mir_library.players[1]
          local ledger = state.mir_library.translations
          local issued = ledger.active[1].pending[1].request_id
          local requests, available_game = #player.translation_requests, game
          assert(view.open and view.refresh_pending and library.subscription_needs())

          -- Loading reconnects only local references. It must not consume the
          -- issued native ID or touch a game/GUI object.
          game = nil
          route_native_events(true)
          native_handlers.load()
          assert(storage == state and storage.mir_library.players[1] == view
            and ledger.active[1].pending[1].request_id == issued
            and view.open and view.refresh_pending)
          game = available_game

          root.destroy()
          native_handlers.events[12]({player_index=1})
          local open, pending = library.native_subscription_needs()
          assert(not open and not pending and not view.open and not view.refresh_pending)
          assert(native_handlers.events[1] == nil and native_ticks[1] == nil)
          assert(#player.translation_requests == requests and player.gui.screen["mir_research_browser"] == nil)
          assert(ledger.active[1] ~= nil and ledger.active[1].pending[1].request_id == issued
            and library.subscription_needs(), "issued IDs remain for bounded expiry cleanup")
          assert(type(native_ticks[61]) == "function")
        ''')

    def test_pending_view_refresh_retires_translation_work_after_the_owned_root_disappears(self):
        self.lua.execute(r'''
          boot_native_events()
          local root=open_routed()
          native_handlers.events[1]({research=gear})
          root.destroy()
          native_ticks[1]({tick=1})
          assert(storage.mir_library.translations.working==nil and native_ticks[1]==nil)
          assert(player.gui.screen["mir_research_browser"]==nil and #player.translation_requests==1)
          assert(library.subscription_needs(),"issued ID was discarded with the working cache")
        ''')

    def test_native_refresh_orders_pending_players_independently_of_saved_map_iteration(self):
        self.lua.execute(r'''
          boot_native_events()
          local order = {}
          player.set_shortcut_toggled = function(_, active) if active then order[#order+1]=1 end end
          local second = {valid=true,index=2,locale="de",connected=true,force=player.force,
            gui={screen=gui_container(nil)},request_translation=function() return nil end,
            set_shortcut_toggled=function(_, active) if active then order[#order+1]=2 end end}
          game.get_player = function(index) return index == 1 and player or index == 2 and second or nil end
          open_routed({status=4})
          assert(remote.interfaces["more-infinite-research-browser"].open(2,{status=4}))
          local views = storage.mir_library.players
          setmetatable(views, {__pairs=function()
            local index=3
            return function() index=index-1; if index>0 then return index,views[index] end end
          end})
          native_handlers.events[1]({research=gear})
          order = {}
          native_ticks[1]({tick=1})
          assert(table.concat(order,",") == "1,2", "pending view order follows hash/insertion traversal")
          assert(native_ticks[1] == nil and storage.mir_library.players[1].query == ""
            and storage.mir_library.players[2].query == "")
        ''')

    def test_authored_catalogue_builds_lazily_once_until_configuration_changes(self):
        self.lua.execute(r'''
          local catalogue = require("research.catalogue")
          local original, builds, family = catalogue.declared, 0, "mir"
          catalogue.declared = function()
            builds = builds + 1
            local rows = original()
            rows[1].family = family
            return rows
          end
          boot()
          library.on_init(); library.on_load()
          assert(builds == 0, "closed Library constructed authored catalogue during parse/init/load")
          local queue, current, progress = player.force.research_queue,
            player.force.current_research, player.force.research_progress
          local root = library.open(player, {selected=gear.name})
          assert(builds == 1, "one Library open rebuilt authored catalogue "..builds.." times")
          local model = require("presentation.library_model")
          local original_rows, observed_level = model.rows, nil
          model.rows = function(force, ...)
            observed_level = force.technologies[gear.name].level
            return original_rows(force, ...)
          end
          gear.level = 4
          local query = research_filters(root)["mir_library_query"]
          query.text = "gear"
          library.on_gui_text_changed({player_index=1,element=query})
          library.close(player)
          library.open(player)
          assert(builds == 1, "refresh/reopen rebuilt unchanged authored metadata")
          assert(observed_level == 4, "metadata cache retained stale native research facts")

          library.close(player)
          family = "research_updated"
          library.on_configuration_changed()
          assert(builds == 1, "configuration rebuilt metadata for a closed Library")
          library.open(player, {family=family})
          assert(builds == 2 and storage.mir_library.players[1].family == family,
            "configuration retained stale authored metadata")
          assert(player.force.research_queue == queue and player.force.current_research == current
            and player.force.research_progress == progress,
            "metadata reuse changed native research state")
        ''')

    def test_native_names_render_before_search_translation_and_in_selected_details(self):
        self.lua.execute(r'''
          boot()
          local gear_name = {"technology-name.more-infinite-research.research_gears", {"item-name.iron-gear-wheel"}}
          local science_name = {"item-name.fixture-science", "native parameter"}
          local prerequisite_name = {"technology-name.fixture-prerequisite"}
          gear.localised_name = gear_name
          library_declarations = {{id=gear.name, name=gear.name, family="research_gears"}}
          player.force.technologies["fixture-prerequisite"] = {valid=true, localised_name=prerequisite_name}
          prototypes = {item = {["fixture-science"]={valid=true, localised_name=science_name}}}
          require("presentation.library_model").detail = function()
            return {cost={count=8000,time=60,ingredients={{name="fixture-science",amount=2}}},
              prerequisites={"fixture-prerequisite"}, effects={}}
          end
          local native_queue = player.force.research_queue
          local root = library.open(player,{selected=gear.name,family="all"})
          local content = research_content(root)
          local detail = content["mir_library_detail"]
          assert(content["mir_library_list_pane"]["mir_library_results"].items[1][3] == gear_name,
            "first-open display exposed an ID while native localized name was available")
          assert(detail.mir_library_research_facts.mir_library_detail_heading["mir_library_detail_title"].caption == gear_name)
          assert(detail.mir_library_research_facts["mir_library_detail_family"] == nil)
          assert(detail.mir_library_research_facts.mir_library_science_icons["mir_library_science_1"].tooltip[2] == science_name)
          assert(detail.mir_library_research_facts.mir_library_prerequisite_icons["mir_library_prerequisite_1"].tooltip == prerequisite_name)
          assert(#player.translation_requests == 3, "display names changed existing search-translation scheduling")
          assert(player.force.research_queue == native_queue)
          -- The current force/prototype is authoritative after a refresh;
          -- do not retain a new display cache or flatten localized parameters.
          local replacement = {"technology-name.replaced-prerequisite", "second parameter"}
          player.force.technologies["fixture-prerequisite"].localised_name = replacement
          library.open(player)
          assert(research_content(root)["mir_library_detail"].mir_library_research_facts.mir_library_prerequisite_icons["mir_library_prerequisite_1"].tooltip == replacement)
        ''')

    def test_missing_or_invalid_native_detail_names_keep_identity_fallbacks(self):
        self.lua.execute(r'''
          boot()
          library_declarations = {{id=gear.name, name=gear.name, family="research_gears"}}
          gear.localised_name = nil
          prototypes = {item=setmetatable({}, {__index=function() error("native item lookup unavailable") end})}
          player.force.technologies["fixture-prerequisite"] = {valid=false,
            localised_name={"technology-name.must-not-appear"}}
          require("presentation.library_model").detail = function()
            return {cost={count=1,time=60,ingredients={{name="missing-science",amount=2}}},
              prerequisites={"fixture-prerequisite","missing-prerequisite"}, effects={}}
          end
          local root = library.open(player,{selected=gear.name,family="all"})
          local content = research_content(root)
          local detail = content["mir_library_detail"]
          assert(content["mir_library_list_pane"]["mir_library_results"].items[1][3] == gear.name)
          assert(detail.mir_library_research_facts["mir_library_detail_family"] == nil)
          assert(detail.mir_library_research_facts.mir_library_science_icons["mir_library_science_1"].caption[2] == "missing-science")
          assert(detail.mir_library_research_facts.mir_library_prerequisite_icons["mir_library_prerequisite_1"].caption == "fixture-prerequisite")
          assert(detail.mir_library_research_facts.mir_library_prerequisite_icons["mir_library_prerequisite_2"].caption == "missing-prerequisite")
        ''')

    def test_requested_view_fits_scaled_display_wraps_details_and_converts_native_ticks(self):
        self.lua.execute(r'''
          boot()
          player.display_resolution, player.display_scale = {width=1280,height=720}, 1.25
          local model = require("presentation.library_model")
          local long_ingredient = "very-long-native-science-ingredient-identifier-for-detail-width"
          model.detail = function()
            return {cost={count=8000,energy=3600,ingredients={{name=long_ingredient,amount=1}}},prerequisites={},
              effects={{type="change-recipe-productivity",change=.10000000149}}}
          end
          local root = library.open(player,{selected=gear.name,query="gear"})
          local root_width = root.style.maximal_width
          assert(root.style.minimal_width == root_width and root_width <= 1280/1.25
            and root.style.maximal_height <= 720/1.25)
          assert(root.auto_center == true and root.force_auto_center_calls == 1)
          local filters = research_filters(root)
          assert(filters.type == "flow" and filters.mir_library_filter_grid.column_count == 2)
          local family_style = filters["mir_library_filter_grid"]["mir_library_family_field"]["mir_library_family"].style
          assert(family_style.minimal_width == family_style.maximal_width and family_style.maximal_width <= 280)
          local content = research_content(root)
          assert(content.type == "table" and content.column_count == 2)
          assert(content.style.maximal_height < root.style.maximal_height and content.style.maximal_width < root_width)
          local detail = content["mir_library_detail"]
          assert(detail.type == "scroll-pane" and detail.horizontal_scroll_policy == "never")
          assert(detail.style.minimal_width < content.style.maximal_width
            and detail.style.maximal_width == 339)
          local cost = content["mir_library_detail"].mir_library_research_facts["mir_library_detail_cost"]
          assert(cost.caption[1] == "mir-browser.research-cost" and tonumber(cost.caption[3]) == 60)
          assert(cost.style.single_line == false and cost.style.maximal_width == detail.style.maximal_width-16)
          local science = detail.mir_library_research_facts.mir_library_science_icons["mir_library_science_1"]
          assert(science.caption[2] == long_ingredient and science.style.maximal_width == detail.style.maximal_width-16)
          assert(content["mir_library_detail"].mir_library_research_facts["mir_library_effect_1"].caption[2] == "10")
          assert(filters["mir_library_filter_grid"]["mir_library_family_field"]["mir_library_family_label"].caption[1] == "mir-browser.filter-scope")
          library.close(player)
          storage.mir_library.players[1].location = {x=17,y=29}
          player.display_resolution, player.display_scale = {width=1280,height=720}, 2
          root = library.open(player,{selected=gear.name})
          assert(research_filters(root).mir_library_filter_grid.column_count == 2)
          assert(root.style.minimal_width == root.style.maximal_width and root.style.maximal_width <= 640
            and root.style.maximal_height <= 360)
          assert(root.location.x == 17 and root.location.y == 29 and root.force_auto_center_calls == nil,
            "a saved drag location must win over native force_auto_center")
          ''')

    def test_explicit_open_restores_native_close_target_and_owned_drag_handle(self):
        self.lua.execute(r'''
          boot()
          local foreign = {valid=true, name="foreign-window"}
          player.opened = foreign
          local root = library.open(player, {query="gear"})
          assert(player.opened == root, "Esc/E cannot close a Library absent from native opened")
          local title = root["mir_library_title"]
          assert(title and title["mir_library_title_label"].caption[1] == "mir-browser.title")
          assert(title["mir_library_title_label"].style_name == "frame_title")
          local drag = title["mir_library_drag"]
          assert(drag and drag.type == "empty-widget" and drag.style_name == "draggable_space_header")
          assert(drag.parent == title and drag.drag_target == root,
            "the draggable widget must be a child of its owned screen frame")
          assert(drag.style.horizontally_stretchable and drag.style.maximal_height == 24)
          root.location = {x=91,y=44}
          library.on_gui_location_changed({player_index=1,element=root})
          -- Native Esc/E emits on_gui_closed for player.opened. Keep the
          -- actual close handler/ownership checks in the path under test.
          library.on_gui_closed({player_index=1,element=player.opened})
          assert(not root.valid and player.gui.screen["mir_research_browser"] == nil)
          assert(storage.mir_library.players[1].query == "gear"
            and storage.mir_library.players[1].location.x == 91)
          local reopened = library.open(player)
          assert(player.opened == reopened and reopened ~= root and reopened.location.y == 44)
          assert(foreign.valid, "opening/closing the Library destroyed a foreign GUI")
        ''')

    def test_science_production_snapshot_is_bounded_read_only_and_refuses_invalid_inputs(self):
        self.lua.execute(r'''
          local production = require("runtime.library_production")
          local force = {valid=true,index=4,name="player",get_item_production_statistics=function(surface)
            assert(surface.index == 2)
            return {valid=true,get_flow_count=function(spec)
              assert(spec.name.quality == "normal" and spec.count == false
                and spec.precision_index == defines.flow_precision_index.one_minute)
              return spec.category == "input" and 12.5 or 4.25
            end}
          end}
          local surface = {valid=true,index=2,name="nauvis"}
          local technology = {valid=true,name="science-tech",force=force,
            research_unit_ingredients={{name="automation-science-pack"},{name="logistic-science-pack"}}}
          defines = {flow_precision_index={one_minute=3}}
          game = {tick=1200}
          local report = assert(production.snapshot({force=force,surface=surface},technology))
          assert(report.tick == 1200 and report.force_name == "player" and report.surface_name == "nauvis")
          assert(#report.rows == 2 and report.rows[1].name == "automation-science-pack"
            and report.rows[1].produced == 12.5 and report.rows[1].consumed == 4.25
            and report.rows[1].balance == 8.25)
          technology.force = {valid=true,index=5}
          assert(production.snapshot({force=force,surface=surface},technology) == nil)
          technology.force = force
          technology.research_unit_ingredients[2] = technology.research_unit_ingredients[1]
          assert(production.snapshot({force=force,surface=surface},technology) == nil)
        ''')

    def test_older_engine_production_statistics_keep_force_scope_and_legacy_flow_arguments(self):
        self.lua.execute(r'''
          local production = require("runtime.library_production")
          local statistics = {valid=true,get_flow_count=function(spec)
            assert(type(spec.name) == "string" and spec.input ~= nil and spec.category == nil
              and spec.precision_index == defines.flow_precision_index.one_minute and spec.count == false)
            return spec.input and 9 or 3
          end}
          local force = {valid=true,index=8,name="player",item_production_statistics=statistics}
          local surface = {valid=true,index=4,name="nauvis"}
          local technology = {valid=true,name="older-science",force=force,
            research_unit_ingredients={{name="automation-science-pack"}}}
          defines = {flow_precision_index={one_minute=2}}
          game = {tick=600}
          local report = assert(production.snapshot({force=force,surface=surface},technology))
          assert(report.scope == "force" and report.surface_name == nil
            and report.rows[1].produced == 9 and report.rows[1].consumed == 3)
          force.item_production_statistics = nil
          assert(production.snapshot({force=force,surface=surface},technology) == nil)
        ''')

    def test_background_library_refresh_does_not_take_native_focus(self):
        self.lua.execute(r'''
          boot()
          local root = library.open(player)
          assert(player.opened == root)
          local foreign = {valid=true, name="foreign-window"}
          player.opened = foreign
          library.on_native_state_changed({force=player.force})
          library.on_native_refresh_tick()
          assert(player.opened == foreign and player.gui.screen["mir_research_browser"] == root,
            "native research refresh took focus from another GUI")
          local request = player.translation_requests[1]
          library.on_string_translated({player_index=1,id=request.id,translated=true,result="Translated gear"})
          assert(player.opened == foreign, "translation refresh took focus from another GUI")
          assert(library.open(player) == root and player.opened == root,
            "an explicit reopen must select the existing owned frame")
        ''')

    def test_tab_navigation_stays_above_tab_specific_controls_and_preserves_personal_view(self):
        self.lua.execute(r'''
          boot()
          local root=library.open(player,{selected=gear.name,search="gear"})
          root.location={x=41,y=17}
          library.on_gui_location_changed({player_index=1,element=root})
          local title,tabs=root.mir_library_title,root.mir_library_tabs
          local page=research_page(root)
          local filters,body=research_filters(root),research_content(root)
          local query=filters.mir_library_query
          assert(root.mir_library_filters==nil and filters.parent==page and body.parent==page,
            "MIR4 keeps Research-only controls below the tabs, inside their own page")
          assert(page.type=="scroll-pane" and page.vertical_scroll_policy=="auto",
            "short windows must scroll inside the page instead of pushing navigation")
          local width,height=root.style.minimal_width,root.style.minimal_height
          local page_height=page.style.minimal_height
          local before_level,before_progress=gear.level,player.force.research_progress
          for _,index in ipairs({2,3,4,1,4,3,2,1}) do
            tabs.selected_tab_index=index
            library.on_gui_selected_tab_changed({player_index=1,element=tabs})
            assert(root==player.gui.screen.mir_research_browser and root.mir_library_title==title
              and root.mir_library_tabs==tabs and filters==research_filters(root) and query==filters.mir_library_query,
              "tab switches must retain the frame, navigation and personal input")
            local live={}
            for _,child in ipairs(root._children) do if child.valid then live[#live+1]=child end end
            assert(#live==2 and live[1]==title and live[2]==tabs,
              "no selected tab may insert a visible control row above navigation")
            assert(root.style.minimal_width==width and root.style.minimal_height==height
              and root.location.x==41 and root.location.y==17)
            for _,name in ipairs({"research_page","queue_content","settings_content","help_content"}) do
              assert(tabs["mir_library_"..name].style.minimal_height==page_height,
                "each tab must occupy the same bounded viewport")
            end
          end
          assert(query.text=="gear" and storage.mir_library.players[1].query=="gear"
            and storage.mir_library.players[1].selected==gear.name)
          assert(gear.level==before_level and player.force.research_progress==before_progress)
          -- A previously saved MIR5 root lacks the per-tab Research page.
          -- Rebuild that owned GUI once without changing the saved view.
          page.destroy()
          root.add{type="table",name="mir_library_filters",column_count=2}
          local replacement=library.open(player)
          assert(replacement~=root and not root.valid and research_page(replacement))
          assert(research_filters(replacement).mir_library_query.text=="gear"
            and storage.mir_library.players[1].selected==gear.name
            and replacement.location.x==41 and replacement.location.y==17)
        ''')

    def test_fractional_display_scale_writes_only_int32_gui_dimensions(self):
        self.lua.execute(r'''
          boot()
          -- 1042 / 1.25 - 32 is 801.6, and the two-column control calculation
          -- is fractional again. The native LuaStyle setters take int32 only.
          player.display_resolution, player.display_scale = {width=1042,height=768}, 1.25
          local root = library.open(player,{selected=gear.name})
          assert(root.style.minimal_width == 640 and root.style.maximal_width == 640)
          assert(root.style.minimal_height == 460 and root.style.maximal_height == 460)
          assert(root.force_auto_center_calls == 1)
          local filters = research_filters(root)
          local family = filters["mir_library_filter_grid"]["mir_library_family_field"]["mir_library_family"]
          assert(family.style.minimal_width == 280 and family.style.maximal_width == 280)
          local tabs = root["mir_library_tabs"]
          assert(tabs.style.maximal_width == 608)
          local content = research_content(root)
          assert(content.style.minimal_width == 592 and content.style.maximal_width == 592)
          assert(content.style.minimal_height == 180 and content.style.maximal_height == 180)
          assert(content.type == "table" and content.column_count == 2)
          assert(content["mir_library_list_pane"]["mir_library_results"].style.minimal_width == 225)
          assert(content["mir_library_detail"].style.minimal_width == 339)
        ''')

    def test_research_library_opens_with_a_selected_split_detail_view(self):
        self.lua.execute(r'''
          boot()
          local root = library.open(player)
          local content = research_content(root)
          local results, detail = content["mir_library_list_pane"]["mir_library_results"], content["mir_library_detail"]
          assert(content.type == "table" and content.column_count == 2)
          assert(results.type == "list-box" and results.selected_index == 1)
          assert(detail.type == "scroll-pane" and detail.vertical_scroll_policy == "auto"
            and detail.horizontal_scroll_policy == "never")
          assert(detail.mir_library_research_facts.mir_library_detail_heading["mir_library_detail_title"].caption == gear.localised_name)
          assert(detail.mir_library_research_facts.mir_library_detail_heading["mir_library_detail_icon"].sprite == "technology/" .. gear.name)
          assert(results.style.maximal_width < detail.style.maximal_width)
          local title = root["mir_library_title"]
          assert(title["mir_library_layout_smaller"] and title["mir_library_layout_larger"]
            and title["mir_library_layout_reset"])

          local settings_root = library.open(player, {tab="settings"})
          local settings_content = settings_root["mir_library_tabs"]["mir_library_settings_content"]
          local panes = settings_content["mir_library_settings_dynamic"]
          assert(panes.type == "table" and panes.column_count == 2)
          assert(panes["mir_library_settings_list"].type == "list-box")
          assert(panes["mir_library_settings_detail"].type == "scroll-pane")
          assert(panes.style.maximal_height < settings_content.style.maximal_height)
          assert(panes["mir_library_settings_list"].style.minimal_height
            == panes["mir_library_settings_detail"].style.minimal_height)
          root = library.open(player, {tab="research", selected=gear.name})
          local actions = research_content(root)["mir_library_list_pane"]["mir_library_actions"]
          assert(actions["mir_library_inspect_settings"].enabled)
          library.on_gui_click({player_index=1, element=actions["mir_library_inspect_settings"]})
          assert(storage.mir_library.players[1].tab == "settings"
            and storage.mir_library.players[1].setting_selected == "research_gears")
        ''')

    def test_affected_recipe_selection_opens_factoriopedia_and_production_check_reads_flow_stats(self):
        self.lua.execute(r'''
          boot()
          local recipe_prototype = {valid=true,name="iron-gear-wheel",localised_name="Gear wheel"}
          gear.prototype.effects = {{type="change-recipe-productivity",recipe="iron-gear-wheel",change=.1}}
          gear.research_unit_ingredients = {{name="automation-science-pack",amount=1}}
          gear.force = player.force
          player.force.valid = true
          player.force.recipes = { ["iron-gear-wheel"] = {
            valid=true,name="iron-gear-wheel",localised_name="Gear wheel",prototype=recipe_prototype
          }}
          local statistics_reads, flow_reads = 0, 0
          player.force.get_item_production_statistics = function(surface)
            assert(surface == player.surface)
            statistics_reads = statistics_reads + 1
            return {valid=true,get_flow_count=function(spec)
              flow_reads = flow_reads + 1
              return spec.category == "input" and 20 or 8
            end}
          end
          player.surface = {valid=true,index=1,name="nauvis"}
          player.open_factoriopedia_gui = function(prototype) player.opened_recipe = prototype end
          defines = {flow_precision_index={one_minute=1}}
          game.tick = 240
          local queue, level = player.force.research_queue, gear.level
          library.open(player, {selected=gear.name})
          local content = research_content(player.gui.screen["mir_research_browser"])
          assert(statistics_reads == 0 and flow_reads == 0,
            "opening research details must not sample production without its explicit action")
          local recipes = content["mir_library_detail"]["mir_library_recipe_list"]
          assert(recipes and #recipes.items == 1 and recipes.items[1][3] == "Gear wheel")
          recipes.selected_index = 1
          library.on_gui_selection_state_changed({player_index=1,element=recipes})
          assert(player.opened_recipe == recipe_prototype)
          player.open_factoriopedia_gui = nil
          library.open(player, {selected=gear.name})
          content = research_content(player.gui.screen["mir_research_browser"])
          assert(statistics_reads == 0 and flow_reads == 0,
            "recipe navigation and rebuilding details must not poll production")
          recipes = content["mir_library_detail"]["mir_library_recipe_list"]
          assert(recipes.tooltip[1] == "mir-browser.recipe-list-only-hint"
            and content["mir_library_detail"]["mir_library_recipe_hint"].caption[1]
              == "mir-browser.recipe-list-only-hint")
          local check = content["mir_library_detail"].mir_library_research_facts["mir_library_production_check"]
          assert(check and check.caption[1] == "mir-browser.production-check")
          local retained_root = player.gui.screen["mir_research_browser"]
          local retained_query = research_filters(retained_root)["mir_library_query"]
          library.on_gui_click({player_index=1,element=check})
          assert(statistics_reads == 1 and flow_reads == 2,
            "one production action must read exactly the selected pack's two rates")
          assert(player.gui.screen["mir_research_browser"] == retained_root
            and research_filters(retained_root)["mir_library_query"] == retained_query,
            "a production action must patch its panel without rebuilding the retained controls")
          local panel = content["mir_library_detail"].mir_library_research_facts["mir_library_production_results"]
          assert(panel["mir_library_production_scope"].caption[1] == "mir-browser.production-scope")
          assert(panel["mir_library_production_snapshot"].caption[2] == "240")
          assert(panel["mir_library_production_row_1"].caption[1] == "mir-browser.production-row")
          assert(queue == player.force.research_queue and gear.level == level)
          player.display_resolution,player.display_scale={width=480,height=600},1.5
          player.opened_recipe=nil
          player.open_factoriopedia_gui=function(prototype) player.opened_recipe=prototype end
          local compact_root=library.open(player,{selected=gear.name})
          local facts=research_content(compact_root).mir_library_detail.mir_library_research_facts
          local compact_recipe=facts.mir_library_recipe_list
          assert(compact_recipe and compact_recipe.parent==facts)
          compact_recipe.selected_index=1
          library.on_gui_selection_state_changed({player_index=1,element=compact_recipe})
          assert(player.opened_recipe==recipe_prototype,"compact recipe navigation must keep working")
          player.opened_recipe=nil
          local wrong=facts.add{type="flow",name="wrong-parent"}
          local foreign=wrong.add{type="list-box",name="mir_library_recipe_list",selected_index=1}
          library.on_gui_selection_state_changed({player_index=1,element=foreign})
          assert(player.opened_recipe==nil,"a same-named control under an unowned parent must be inert")
          library.close(player)
          library.on_gui_click({player_index=1,element=check})
          assert(statistics_reads == 1 and flow_reads == 2,
            "a retired production action must not sample or reopen the closed Library")
        ''')

    def test_selected_live_productivity_limits_and_saturation_render_without_stale_values(self):
        self.lua.execute('''
          package.preload["presentation.library_model"] = nil
          package.loaded["presentation.library_model"] = nil
          boot()
          gear.researched, gear.enabled = false, true
          gear.level = 1
          player.force.research_queue, player.force.current_research = {}, nil
          gear.prototype.effects = {{type="change-recipe-productivity",recipe="gear",change=.1}}
          local recipe = {valid=true,name="gear",localised_name="Gear",productivity_bonus=0,
            prototype={maximum_productivity=3}}
          player.force.recipes = {gear=recipe}
          local function detail()
            local root = library.open(player,{selected=gear.name})
            return research_content(root)["mir_library_detail"].mir_library_research_facts
          end
          local first = detail()
          assert(first["mir_library_productivity_current_cap"]
            and first["mir_library_productivity_current_cap"].caption[2] == "0"
            and first["mir_library_productivity_current_cap"].caption[3] == "300",
            "selected details must show the actual recipe bonus and maximum")
          assert(first["mir_library_no_next_benefit"] == nil)
          recipe.productivity_bonus = 3
          local saturated = detail()
          assert(saturated["mir_library_productivity_current_cap"].caption[2] == "300"
            and saturated["mir_library_no_next_benefit"].caption[1] == "mir-browser.no-next-benefit")
          gear.prototype.effects[2] = {type="change-recipe-productivity",recipe="other-gear",change=.2}
          player.force.recipes["other-gear"] = {valid=true,name="other-gear",localised_name="Other gear",
            productivity_bonus=1.5,prototype={maximum_productivity=5}}
          recipe.productivity_bonus = .25
          local mixed = detail()["mir_library_productivity_current_cap"].caption
          assert(mixed[1] == "mir-browser.productivity-current-cap-range"
            and mixed[2] == "25" and mixed[3] == "150" and mixed[4] == "300" and mixed[5] == "500")
          recipe.productivity_bonus = 3
          player.force.recipes["other-gear"].productivity_bonus = 5
          gear.prototype.effects[3] = {type="unlock-recipe",recipe="another-benefit"}
          assert(detail()["mir_library_no_next_benefit"] == nil,
            "saturated recipe productivity must not deny other kinds of native benefit")
          gear.prototype.effects = {{type="change-recipe-productivity",recipe="gear",change=.1}}
          player.force.recipes.gear = nil
          local missing = detail()
          assert(missing["mir_library_live_detail_unavailable"].caption[1] == "mir-browser.live-detail-unavailable"
            and missing["mir_library_productivity_current_cap"] == nil
            and missing["mir_library_no_next_benefit"] == nil,
            "missing live facts must replace stale numbers without claiming saturation")
          player.force.recipes.gear = recipe
          recipe.prototype.maximum_productivity = 1e308
          assert(detail()["mir_library_live_detail_unavailable"] ~= nil,
            "unrepresentable percentages must not display invented infinite limits")
          assert(gear.level == 1 and gear.enabled and not gear.researched
            and #player.force.research_queue == 0)
        ''')

    def test_legacy_engine_prototype_collections_supply_library_recipe_and_item_names(self):
        self.lua.execute(r'''
          boot()
          prototypes = nil
          local recipe_name = {"recipe-name.iron-gear-wheel"}
          local item_name = {"item-name.automation-science-pack"}
          local recipe = {valid=true, name="iron-gear-wheel", localised_name=recipe_name,
            products={{type="item", name="automation-science-pack"}}}
          game.recipe_prototypes = { [recipe.name] = recipe }
          game.item_prototypes = { ["automation-science-pack"] = {
            valid=true, name="automation-science-pack", localised_name=item_name
          }}
          game.fluid_prototypes = {}
          gear.prototype.effects = {{type="unlock-recipe", recipe=recipe.name}}
          gear.research_unit_ingredients = {{name="automation-science-pack", amount=1}}
          gear.force = player.force
          player.force.valid = true
          player.force.item_production_statistics = {valid=true, get_flow_count=function(spec)
            assert(type(spec.name) == "string" and spec.input ~= nil and spec.category == nil)
            return spec.input and 12 or 4
          end}
          player.surface = {valid=true, index=1, name="nauvis"}
          defines = {flow_precision_index={one_minute=1}}
          game.tick = 600

          local root = library.open(player, {selected=gear.name})
          local function contains(value, target)
            if value == target then return true end
            if type(value) ~= "table" then return false end
            for _, child in ipairs(value) do if contains(child, target) then return true end end
            return false
          end
          assert(#player.translation_requests == 1
            and contains(player.translation_requests[1].localised, recipe_name[1])
            and contains(player.translation_requests[1].localised, item_name[1]),
            "Factorio 1.x game prototype collections must supply localized search names")

          local content = research_content(root)
          local detail = content["mir_library_detail"]
          local recipes = detail["mir_library_recipe_list"]
          assert(recipes and #recipes.items == 1 and recipes.items[1][3] == recipe_name,
            "the affected-recipe list must resolve through game.recipe_prototypes")
          local check = detail.mir_library_research_facts["mir_library_production_check"]
          library.on_gui_click({player_index=1, element=check})
          local production = detail.mir_library_research_facts["mir_library_production_results"]["mir_library_production_row_1"]
          assert(production and production.caption[2] == item_name,
            "the science snapshot must resolve names through game.item_prototypes")
        ''')

    def test_narrow_display_uses_a_scrollable_stacked_library(self):
        self.lua.execute(r'''
          boot()
          player.display_resolution, player.display_scale = {width=480,height=600}, 1.5
          local root = library.open(player, {selected=gear.name})
          local content = research_content(root)
          assert(content.type == "scroll-pane" and content.vertical_scroll_policy == "auto")
          assert(content["mir_library_list_pane"]["mir_library_actions"] and content["mir_library_list_pane"]["mir_library_results"]
            and content["mir_library_detail"])
          assert(content["mir_library_list_pane"]["mir_library_results"].style.minimal_height >= 76
            and content["mir_library_detail"].style.minimal_height >= 80)
          assert(content["mir_library_list_pane"]["mir_library_results"].style.maximal_width
            == content["mir_library_detail"].style.maximal_width
            and content["mir_library_list_pane"]["mir_library_results"].style.maximal_width <= content.style.maximal_width)
        ''')

    def test_title_close_button_closes_the_library_from_every_tab(self):
        self.lua.execute(r'''
          boot()
          local root = library.open(player, {tab="settings"})
          local close = root["mir_library_title"]["mir_library_close"]
          assert(close and close.sprite == "utility/close")
          library.on_gui_click({player_index=1, element=close})
          assert(root.valid == false and storage.mir_library.players[1].open == false)
        ''')

    def test_filter_click_is_inert_and_native_selection_updates_the_retained_window(self):
        self.lua.execute(r'''
          boot()
          local model = require("presentation.library_model")
          local original_rows, row_calls = model.rows, 0
          model.rows = function(...)
            row_calls = row_calls + 1
            return original_rows(...)
          end

          local root = library.open(player)
          local filters = research_filters(root)
          local status = filters["mir_library_filter_grid"]["mir_library_status_field"]["mir_library_status"]
          local query = filters["mir_library_query"]
          local initial_rows = row_calls
          library.on_gui_click({player_index=1, element=status})
          assert(row_calls == initial_rows,
            "clicking a native dropdown must not fall through to a catalogue rebuild")
          assert(player.gui.screen["mir_research_browser"] == root
            and filters["mir_library_filter_grid"]["mir_library_status_field"]["mir_library_status"] == status
            and filters["mir_library_query"] == query and status.valid and query.valid,
            "an inert dropdown click must keep the retained controls alive")

          status.selected_index = 4
          library.on_gui_selection_state_changed({player_index=1, element=status})
          assert(row_calls > initial_rows and storage.mir_library.players[1].status == 4,
            "the separate native selection event must apply the selected filter")
          assert(player.gui.screen["mir_research_browser"] == root
            and research_filters(root)["mir_library_filter_grid"]["mir_library_status_field"]["mir_library_status"] == status
            and research_filters(root)["mir_library_query"] == query,
            "filter selection must update the retained view without replacing the window or query")
        ''')

    def test_layout_controls_resize_reset_and_rebuild_an_outdated_saved_window(self):
        self.lua.execute(r'''
          boot()
          local root = library.open(player, {selected=gear.name})
          assert(root.style.minimal_width == 640 and root.style.minimal_height == 540)
          local title = root["mir_library_title"]
          root.location = {x=1200,y=680}
          library.on_gui_location_changed({player_index=1, element=root})
          library.on_gui_click({player_index=1, element=title["mir_library_layout_larger"]})
          assert(root.style.minimal_width == 704 and root.style.minimal_height == 604)
          assert(storage.mir_library.players[1].geometry.width == 704)
          assert(root.location.x <= player.display_resolution.width - root.style.maximal_width * player.display_scale
            and root.location.y <= player.display_resolution.height - root.style.maximal_height * player.display_scale)
          library.on_gui_click({player_index=1, element=title["mir_library_layout_smaller"]})
          assert(root.style.minimal_width == 640 and root.style.minimal_height == 540)
          root.location = {x=81,y=42}
          library.on_gui_location_changed({player_index=1, element=root})
          library.on_gui_click({player_index=1, element=title["mir_library_layout_reset"]})
          assert(root.style.minimal_width == 640 and root.style.minimal_height == 540)
          assert(storage.mir_library.players[1].geometry == nil and storage.mir_library.players[1].location == nil)
          assert(root.force_auto_center_calls == 2)

          local old = root
          old["mir_library_title"]["mir_library_layout_smaller"].destroy()
          research_content(old).type = "scroll-pane"
          root = library.open(player)
          assert(root and root ~= old and research_content(root).type == "table")
          assert(root["mir_library_title"]["mir_library_layout_smaller"] ~= nil)
          assert(storage.mir_library.players[1].selected == gear.name)
        ''')

    def test_legacy_remote_search_uses_selected_or_retained_tab_without_cross_query_writes(self):
        self.lua.execute(r'''
          boot()
          library.open(player, {query="gear", page=7})
          local before_level, before_queue = gear.level, player.force.research_queue
          local options = {tab="settings", settings_scope="options", search="repair"}
          library.open(player, options)
          local view = storage.mir_library.players[1]
          assert(view.settings_query == "repair" and view.query == "gear",
            "legacy settings search must leave the research query unchanged")
          assert(view.page == 1, "legacy search must retain its published remote page reset")
          assert(options.search == "repair" and options.query == nil,
            "legacy search options must remain caller-owned")
          library.open(player, {search="default"})
          view = storage.mir_library.players[1]
          assert(view.tab == "settings" and view.settings_query == "default" and view.query == "gear",
            "legacy search without a tab must use the retained settings tab")
          library.open(player, {search=""})
          view = storage.mir_library.players[1]
          assert(view.settings_query == "" and view.query == "gear",
            "empty legacy settings search must clear only that query")
          library.open(player, {tab="research", search="copper"})
          view = storage.mir_library.players[1]
          assert(view.query == "copper" and view.settings_query == "",
            "legacy research search must leave the settings query unchanged")
          library.open(player, {tab="settings", search=string.rep("x", 161)})
          view = storage.mir_library.players[1]
          assert(view.settings_query == string.rep("x", 160) and view.query == "copper",
            "legacy settings search must retain the published 160-byte bound")
          library.open(player, {search="legacy", settings_search="explicit", query="iron"})
          view = storage.mir_library.players[1]
          assert(view.settings_query == "explicit" and view.query == "iron",
            "explicit internal query fields must retain their separate meanings")
          assert(gear.level == before_level and player.force.research_queue == before_queue,
            "legacy search must not change native research or queue state")
        ''')

    def test_repeated_resize_stays_within_display_bounds(self):
        self.lua.execute(r'''
          boot()
          local root = library.open(player, {selected=gear.name})
          local title = root["mir_library_title"]
          for _ = 1, 20 do
            library.on_gui_click({player_index=1, element=title["mir_library_layout_larger"]})
          end
          local geometry = storage.mir_library.players[1].geometry
          assert(geometry.width == 1256 and geometry.height == 696)
          assert(root.style.maximal_width == geometry.width and root.style.maximal_height == geometry.height)
          library.on_gui_click({player_index=1, element=title["mir_library_layout_smaller"]})
          assert(storage.mir_library.players[1].geometry.width < geometry.width
            and storage.mir_library.players[1].geometry.height < geometry.height)
        ''')

    def test_layout_tables_recreate_for_column_changes_and_never_mutate_column_count(self):
        self.lua.execute(r'''
          boot()
          local root = library.open(player, {query="gear"})
          local original_root = root
          assert(research_filters(root).mir_library_filter_grid.column_count == 2)
          local filters = research_filters(root)
          filters["mir_library_filter_grid"]["mir_library_mode_field"]["mir_library_mode"].selected_index = 3
          library.on_gui_selection_state_changed({player_index=1, element=filters["mir_library_filter_grid"]["mir_library_mode_field"]["mir_library_mode"]})
          filters = research_filters(root)
          filters["mir_library_filter_grid"]["mir_library_status_field"]["mir_library_status"].selected_index = 4
          library.on_gui_selection_state_changed({player_index=1, element=filters["mir_library_filter_grid"]["mir_library_status_field"]["mir_library_status"]})
          filters = research_filters(root)
          filters["mir_library_filter_grid"]["mir_library_sort_field"]["mir_library_sort"].selected_index = 3
          library.on_gui_selection_state_changed({player_index=1, element=filters["mir_library_filter_grid"]["mir_library_sort_field"]["mir_library_sort"]})
          local original_tabs = root["mir_library_tabs"]
          for _ = 1, 3 do
            local larger = root["mir_library_title"]["mir_library_layout_larger"]
            library.on_gui_click({player_index=1, element=larger})
            root = player.gui.screen["mir_research_browser"]
          end
          assert(storage.mir_library.players[1].geometry.width == 832)
          assert(root == original_root and root.valid,
            "resizing the filters must retain the Library window")
          assert(original_tabs.valid and root["mir_library_tabs"] == original_tabs,
            "resizing within a split layout retains navigation and search")
          local live_children = {}
          for _, child in ipairs(root._children) do
            if child.valid then live_children[#live_children + 1] = child end
          end
          assert(#live_children == 2 and live_children[1] == root["mir_library_title"]
            and live_children[2] == root["mir_library_tabs"],
            "Research controls must stay inside their tab, below stable navigation")
          assert(research_filters(root).parent == research_page(root))
          assert(research_filters(root).mir_library_filter_grid.column_count == 2,
            "authored fields remain two columns as the window grows")
          filters = research_filters(root)
          assert(filters["mir_library_query"].text == "gear"
            and filters["mir_library_filter_grid"]["mir_library_mode_field"]["mir_library_mode"].selected_index == 3
            and filters["mir_library_filter_grid"]["mir_library_status_field"]["mir_library_status"].selected_index == 4
            and filters["mir_library_filter_grid"]["mir_library_sort_field"]["mir_library_sort"].selected_index == 3,
            "recreated GUI controls must reflect the saved per-player filter state")

          root = library.open(player, {tab="settings", settings_scope="options", settings_search=""})
          local view = storage.mir_library.players[1]
          local selected_setting = view.setting_selected
          assert(view.settings_scope == "options" and selected_setting ~= nil)
          local settings = root["mir_library_tabs"]["mir_library_settings_content"]["mir_library_settings_dynamic"]
          assert(settings.column_count == 2)
          player.display_resolution = {width=480,height=400}
          root = library.open(player, {tab="settings"})
          view = storage.mir_library.players[1]
          assert(view.settings_scope == "options" and view.settings_query == ""
            and view.setting_selected == selected_setting,
            "narrow-layout reconstruction must preserve saved settings scope, query and selection")
          settings = root["mir_library_tabs"]["mir_library_settings_content"]["mir_library_settings_dynamic"]
          assert(settings.column_count == 1,
            "the settings detail table must be recreated as a stacked layout on a narrow display")

          root = library.open(player, {tab="availability"})
          assert(root == player.gui.screen["mir_research_browser"])
          assert(research_content(root).type == "scroll-pane",
            "a narrow single-column view must use a scroll pane without changing its column count")
        ''')

    def test_hide_show_and_restore_actions_are_personal_and_keep_native_research_unchanged(self):
        self.lua.execute(r'''
          boot()
          local model = require("presentation.library_model")
          local original_rows = model.rows
          model.rows = function(force, declarations, view, labels, context)
            local rows, visible = original_rows(force, declarations, view, labels, context), {}
            for _, row in ipairs(rows) do
              row.hidden = view.hidden[row.id] == true
              if (view.visibility == 1 and not row.hidden) or (view.visibility == 2 and row.hidden) then
                visible[#visible + 1] = row
              end
            end
            return visible
          end
          local queue, level = player.force.research_queue, gear.level
          local root = library.open(player, {selected=gear.name})
          local content = research_content(root)
          assert(content["mir_library_list_pane"]["mir_library_actions"]["mir_library_hide"].sprite == "utility/collapse")
          library.on_gui_click({player_index=1, element=content["mir_library_list_pane"]["mir_library_actions"]["mir_library_hide"]})
          assert(storage.mir_library.players[1].hidden[gear.name] == true)
          assert(#content["mir_library_list_pane"]["mir_library_results"].items == 0)
          assert(player.force.research_queue == queue and gear.level == level)

          local filters = research_filters(root)
          filters["mir_library_filter_grid"]["mir_library_visibility_field"]["mir_library_visibility"].selected_index = 2
          library.on_gui_selection_state_changed({player_index=1, element=filters["mir_library_filter_grid"]["mir_library_visibility_field"]["mir_library_visibility"]})
          assert(content["mir_library_list_pane"]["mir_library_results"].selected_index == 1)
          assert(content["mir_library_list_pane"]["mir_library_actions"]["mir_library_hide"].sprite == "utility/expand"
            and content["mir_library_list_pane"]["mir_library_actions"]["mir_library_hide"].tooltip[1] == "mir-browser.show-tooltip")
          library.on_gui_click({player_index=1, element=content["mir_library_list_pane"]["mir_library_actions"]["mir_library_hide"]})
          assert(storage.mir_library.players[1].hidden[gear.name] == nil
            and storage.mir_library.players[1].visibility == 1)
          assert(#content["mir_library_list_pane"]["mir_library_results"].items == 1 and content["mir_library_list_pane"]["mir_library_results"].selected_index == 1)

          library.on_gui_click({player_index=1, element=content["mir_library_list_pane"]["mir_library_actions"]["mir_library_hide"]})
          filters["mir_library_filter_grid"]["mir_library_visibility_field"]["mir_library_visibility"].selected_index = 2
          library.on_gui_selection_state_changed({player_index=1, element=filters["mir_library_filter_grid"]["mir_library_visibility_field"]["mir_library_visibility"]})
          library.on_gui_click({player_index=1, element=content["mir_library_list_pane"]["mir_library_actions"]["mir_library_show_hidden"]})
          assert(next(storage.mir_library.players[1].hidden) == nil
            and storage.mir_library.players[1].visibility == 1)
          assert(player.force.research_queue == queue and gear.level == level)
        ''')

    def test_two_players_reject_malformed_hidden_replacements_without_changing_views_or_research(self):
        self.lua.execute(r'''
          package.preload["presentation.library_model"] = nil
          package.loaded["presentation.library_model"] = nil
          boot()
          local peer = {valid=true, index=2, name="Bob", locale="de", connected=true,
            force=player.force, gui={screen=gui_container(nil)},
            display_resolution=player.display_resolution, display_scale=1}
          game.get_player = function(index) return index==1 and player or index==2 and peer or nil end

          -- Preserve the old fixture's full active-force witness rather than
          -- treating unchanged levels alone as unchanged native research.
          gear.saved_progress, foreign.saved_progress = .125, .25
          local function snapshot()
            local force, parts = player.force, {}
            local names = {}; for name in pairs(force.technologies) do names[#names+1]=name end
            table.sort(names)
            for _, name in ipairs(names) do
              local tech=force.technologies[name]
              for _, key in ipairs({"name","level","researched","enabled","visible_when_disabled","saved_progress"}) do
                parts[#parts+1]=name..":"..key.."="..tostring(tech[key])
              end
            end
            parts[#parts+1]="current="..force.current_research.name
            parts[#parts+1]="progress="..force.research_progress
            for index, tech in ipairs(force.research_queue) do parts[#parts+1]=index.."="..tech.name end
            return table.concat(parts,"|")
          end
          local native_before = snapshot()
          local root_a=library.open(player,{family="all",mode=1,hidden={gear.name},selected=foreign.name})
          local root_b=library.open(peer,{family="all",mode=3,hidden={},selected=gear.name})
          local function assert_views()
            local a,b=storage.mir_library.players[1],storage.mir_library.players[2]
            assert(a~=b and a.hidden~=b.hidden and a.mode==1 and b.mode==3,
              "players sharing a force must retain distinct personal views and hidden tables")
            assert(a.hidden[gear.name] and not a.hidden[foreign.name] and next(b.hidden)==nil,
              "invalid replacement or another player's action changed personal hidden choices")
            local ca,cb=research_content(root_a),research_content(root_b)
            assert(#ca.mir_library_list_pane.mir_library_results.items==1
              and ca.mir_library_list_pane.mir_library_results.items[1][3]==foreign.localised_name
              and a.selected==foreign.name and ca.mir_library_list_pane.mir_library_actions.mir_library_hide.sprite=="utility/collapse",
              "malformed hidden replacement changed the prior visible selection or action")
            assert(#cb.mir_library_list_pane.mir_library_results.items==1
              and cb.mir_library_list_pane.mir_library_results.items[1][3]==gear.localised_name
              and b.selected==gear.name and cb.mir_library_list_pane.mir_library_actions.mir_library_hide.sprite=="utility/collapse")
            assert(snapshot()==native_before,"Library personal views changed active native research")
          end
          assert_views()
          -- These three literal invalid payloads come from the historical
          -- personal-continuity fixture, independently of current validation.
          for _, invalid in ipairs({{[2]=gear.name},{gear.name,gear.name},{"no-such-technology"}}) do
            root_a=library.open(player,{hidden=invalid})
            assert_views()
          end

          library.open(player,{hidden={}})
          assert(next(storage.mir_library.players[1].hidden)==nil
            and #research_content(root_a).mir_library_list_pane.mir_library_results.items==2,
            "a valid empty replacement must actually clear the personal hidden list")
          root_a=library.open(player,{hidden={gear.name},selected=foreign.name})
          assert_views()
          -- Host reconstruction is a control, not a real save/reload result.
          library.on_load()
          root_a=library.open(player); root_b=library.open(peer)
          assert_views()
        ''')

    def test_limited_discovery_warning_is_personal_retained_and_uses_the_existing_count(self):
        self.lua.execute(r'''
          package.preload["presentation.library_model"] = nil
          package.loaded["presentation.library_model"] = nil
          boot()
          prototypes={recipe={},item={},fluid={}}
          gear.prototype.effects={}
          for index=1,129 do
            local id="recipe-"..index
            gear.prototype.effects[index]={type="unlock-recipe",recipe=id}
            prototypes.recipe[id]={localised_name=id,products={}}
          end
          local queue,current,progress=player.force.research_queue,player.force.current_research,player.force.research_progress
          local root=library.open(player,{selected=gear.name})
          local query=research_filters(root).mir_library_query
          local function indicator(frame)
            local content=research_content(frame)
            return content.mir_library_list_pane.mir_library_count
          end
          assert(indicator(root).tooltip and indicator(root).tooltip[1]=="mir-browser.discovery-limited",
            "limited localized discovery must warn on the existing result count")
          local request=player.translation_requests[1].id
          local fields={gear.localised_name}; for index=1,128 do fields[#fields+1]="recipe-"..index end
          library.on_string_translated{player_index=1,id=request,translated=true,result=table.concat(fields,"\31")}
          assert(indicator(root).tooltip[1]=="mir-browser.discovery-limited")
          assert(root==player.gui.screen.mir_research_browser and query==research_filters(root).mir_library_query)

          local peer={valid=true,index=2,name="Bob",locale="de",connected=true,force=player.force,
            gui={screen=gui_container(nil)},display_resolution=player.display_resolution,display_scale=1}
          game.get_player=function(index)return index==1 and player or index==2 and peer or nil end
          local peer_root=library.open(peer,{family="external"})
          assert(indicator(peer_root).tooltip==nil,"one player's bounded discovery warned an unrelated peer view")
          local working=storage.mir_library.translations.working[1].cache
          local epoch=storage.mir_library.translations.next_epoch
          package.loaded["runtime.library"]=nil
          library=require("runtime.library")
          local available_game=game;game=nil;library.on_load();game=available_game
          assert(storage.mir_library.translations.working[1].cache==working
            and storage.mir_library.translations.next_epoch==epoch,
            "cold-load reconnection changed durable discovery work")
          root=library.open(player)
          assert(#player.translation_requests==1 and indicator(root).tooltip[1]=="mir-browser.discovery-limited",
            "cold-load lost settled discovery limits or issued duplicate requests")
          player.display_resolution={width=480,height=400}
          root=library.open(player)
          assert(research_content(root).mir_library_list_pane.mir_library_count.tooltip[1]=="mir-browser.discovery-limited",
            "narrow layout lost the count warning")
          assert(indicator(peer_root).tooltip==nil)
          library.close(player);gear.prototype.effects={}
          root=library.open(player)
          assert(indicator(root).tooltip==nil,"a new complete discovery scope kept an old warning")
          assert(player.force.research_queue==queue and player.force.current_research==current
            and player.force.research_progress==progress and gear.level==3 and gear.enabled==false)
        ''')

    def test_actual_discovery_transport_and_callback_failures_warn_without_changing_research(self):
        self.lua.execute(r'''
          for _,opponent in ipairs({"transport","failed-callback","partial-composition"}) do
            boot()
            prototypes={recipe={casting={localised_name="Casting",products={{type="item",name="gold"}}}},
              item={gold={localised_name="Gold"}},fluid={}}
            gear.prototype.effects={{type="unlock-recipe",recipe="casting"}}
            if opponent=="transport" then player.request_translation=function()error("native transport refusal")end end
            local queue,current,progress=player.force.research_queue,player.force.current_research,player.force.research_progress
            local root=library.open(player)
            if opponent~="transport" then
              library.on_string_translated{player_index=1,id=player.translation_requests[1].id,
                translated=opponent~="failed-callback",result="Gear\31Casting"}
            end
            local content=research_content(root)
            local count=content.mir_library_list_pane.mir_library_count
            assert(count.tooltip and count.tooltip[1]=="mir-browser.discovery-limited",
              "actual host lost discovery failure metadata: "..opponent)
            local ledger=storage.mir_library.translations
            assert(ledger.active[1]==nil and ledger.working[1].cache.labels[gear.name]==nil,
              "failed discovery kept a native slot or published partial text")
            assert(player.force.research_queue==queue and player.force.current_research==current
              and player.force.research_progress==progress and gear.level==3 and gear.enabled==false)
          end
        ''')

    def test_older_discovery_cache_renews_only_on_open_and_retains_issued_request_rights(self):
        self.lua.execute(r'''
          boot()
          prototypes={recipe={casting={localised_name="Casting",products={}}},item={},fluid={}}
          gear.prototype.effects={{type="unlock-recipe",recipe="casting"}}
          local root=library.open(player)
          local ledger=storage.mir_library.translations
          local cache=ledger.working[1].cache
          -- Exact pre-correction working-cache shape: the issued ledger has
          -- no new fields, while derived work lacks discovery coverage data.
          cache.discovery_subjects,cache.discovery_limited=nil,nil
          local old_epoch,old_generation=ledger.next_epoch,cache.generation
          local first=player.translation_requests[1].id
          gear.prototype.effects={}
          package.loaded["runtime.library"]=nil;library=require("runtime.library")
          local available_game=game;game=nil;library.on_load();game=available_game
          assert(cache.discovery_subjects==nil and cache.discovery_limited==nil
            and cache.generation==old_generation and ledger.next_epoch==old_epoch
            and #ledger.active[1].pending==1,"on_load migrated older discovery work")
          root=library.open(player)
          assert(ledger.next_epoch==old_epoch+1 and cache.generation==old_generation+1
            and #player.translation_requests==2 and #ledger.active[1].pending==2,
            "valid open did not renew derived coverage while retaining the old issued slot")
          local allowed={request_id=true,key=true,scope=true,cache_generation=true,requested_tick=true}
          for _,pending in ipairs(ledger.active[1].pending) do
            local fields=0
            for key in pairs(pending) do assert(allowed[key],"discovery metadata changed the issued-ID ledger");fields=fields+1 end
            assert(fields==5)
          end
          library.on_string_translated{player_index=1,id=first,translated=true,result="invalid old composition"}
          assert(#ledger.active[1].pending==1)
          local content=research_content(root)
          local count=content.mir_library_list_pane.mir_library_count
          assert(count.tooltip==nil,"an old-scope discovery callback contaminated the renewed view")
          library.on_string_translated{player_index=1,id=player.translation_requests[2].id,
            translated=true,result="Complete current caption"}
          assert(ledger.active[1]==nil and cache.labels[gear.name]=="Complete current caption")
        ''')

    def test_unknown_saved_discovery_metadata_is_preserved_without_another_native_window(self):
        self.lua.execute(r'''
          boot()
          library.open(player)
          local ledger=storage.mir_library.translations
          local saved=ledger.working[1]
          saved.cache.discovery_limited="unknown-future-shape"
          local pending,epoch=ledger.active[1],ledger.next_epoch
          package.loaded["runtime.library"]=nil;library=require("runtime.library")
          local available_game=game;game=nil;library.on_load();game=available_game
          library.open(player)
          assert(ledger.working[1]==saved and saved.cache.discovery_limited=="unknown-future-shape"
            and ledger.active[1]==pending and ledger.next_epoch==epoch,
            "unrecognized saved discovery metadata or its issued rights were replaced")
          assert(#player.translation_requests==1,"unknown working metadata opened a second request window")
        ''')

    def test_pure_prototype_constructor_preserves_published_shortcut_identity(self):
        self.lua.globals().prototype_source = (ROOT / "source/presentation/shortcut.lua").as_posix()
        self.lua.execute('''
          local presentation = assert(loadfile(prototype_source))()
          local base = presentation.research_library_shortcut(false)
          assert(base.type == "shortcut" and base.name == "mir-research-browser")
          assert(base.action == "lua" and base.toggleable and base.order == "z[more-infinite-research]-a[research-browser]")
          assert(base.icon == "__base__/graphics/icons/lab.png" and base.icon_size == 64)
          local space_age = presentation.research_library_shortcut(true)
          assert(space_age.icon == "__space-age__/graphics/technology/research-productivity.png" and space_age.icon_size == 256)
          assert(base ~= space_age and base.small_icon == base.icon and space_age.small_icon == space_age.icon)
        ''')

    def test_all_shipped_locales_cover_the_recovered_library_tab_surface(self):
        required = {
            "availability", "availability-empty", "configuration-source", "count", "effective-values",
            "help", "help-summary", "productivity-increment", "queue-empty", "queue-tab",
            "not-added", "productivity-current-cap", "productivity-current-cap-range",
            "no-next-benefit", "live-detail-unavailable",
            "report-options", "report-settings", "report-omissions", "report-preview", "report-select", "report-local",
            "debug-refresh", "discovery-limited",
            "search-settings", "hide", "show", "show-hidden", "inspect-settings", "hide-tooltip",
            "show-tooltip", "layout-smaller",
            "layout-larger", "layout-reset",
            "science-ingredient", "scope-startup", "setting-off", "setting-on", "setting-provenance",
            "settings", "settings-count", "settings-empty", "settings-scope-options",
            "settings-scope-research", "source-direct", "source-mirset1",
        }
        locales = sorted((ROOT / "source/locale").glob("*/mir-library.cfg"))
        self.assertEqual(len(locales), 50)
        for path in locales:
            keys = {line.split("=", 1)[0] for line in path.read_text(encoding="utf-8").splitlines()
                    if line and not line.startswith((";", "#", "[")) and "=" in line}
            self.assertTrue(required <= keys, path)

    def test_en_and_de_localize_the_authored_availability_reasons(self):
        required = {
            "availability-entry", "availability-requires-space-age", "availability-native-research-productivity",
            "availability-not-available-in-bob-angel-profile", "availability-not-available-in-bobtech-angel-profile",
        }
        for language in ("en", "de"):
            path = ROOT / "source/locale" / language / "mir-library.cfg"
            keys = {line.split("=", 1)[0] for line in path.read_text(encoding="utf-8").splitlines()
                    if line and not line.startswith((";", "#", "[")) and "=" in line}
            self.assertTrue(required <= keys, path)
            names = ROOT / "source/locale" / language / "more-infinite-research.cfg"
            name_keys = {line.split("=", 1)[0] for line in names.read_text(encoding="utf-8").splitlines()
                         if line and not line.startswith((";", "#", "[")) and "=" in line}
            self.assertTrue({
                "more-infinite-research.research_agricultural_growth_speed",
                "more-infinite-research.research_spoilage_preservation",
                "more-infinite-research.research_lab_productivity",
            } <= name_keys, names)

    def test_availability_mode_searches_authored_rows_without_native_actions(self):
        self.lua.execute(r'''
          script = {active_mods = {}}
          boot()
          local native_queue, native_current, native_progress = player.force.research_queue,
            player.force.current_research, player.force.research_progress

          local root = library.open(player, {tab = "availability"})
          local content = research_content(root)
          assert(content["mir_library_availability_1"] ~= nil and content["mir_library_availability_2"] ~= nil
            and content["mir_library_availability_empty"] == nil)
          local query = research_filters(root)["mir_library_query"]
          query.text = "spoilage-preservation"
          library.on_gui_text_changed({player_index = 1, element = query})
          assert(content["mir_library_availability_1"].caption[2][1]
              == "technology-name.more-infinite-research.research_spoilage_preservation"
            and content["mir_library_availability_2"] == nil)

          script.active_mods = {["space-age"] = "2.1.23"}
          query.text = ""
          library.on_gui_text_changed({player_index = 1, element = query})
          assert(content["mir_library_availability_empty"] ~= nil,
            "Space Age must not show the two requires-Space-Age rows")

          local owner = {valid = true, prototype = {effects = {
            {type = "laboratory-productivity", modifier = .1}
          }}}
          player.force.technologies["research-productivity"] = owner
          library.open(player, {tab = "availability", query = "lab"})
          assert(content["mir_library_availability_1"].caption[2][1]
              == "technology-name.more-infinite-research.research_lab_productivity"
            and content["mir_library_availability_1"].caption[3][1]
              == "mir-browser.availability-native-research-productivity")

          owner.prototype.effects[1].modifier = .1001
          library.open(player, {tab = "availability", query = ""})
          assert(content["mir_library_availability_empty"] ~= nil
            and content["mir_library_availability_1"] == nil,
            "a malformed named native owner must not produce an explanation")
          assert(player.force.research_queue == native_queue and player.force.current_research == native_current
            and player.force.research_progress == native_progress and gear.level == 3 and gear.enabled == false)
        ''')

    def test_availability_uses_parse_time_effective_streams_without_profile_resolution_on_refresh(self):
        self.lua.execute(r'''
          local loads, rows_calls = 0, 0
          local streams = {research_material_lead = {enabled = false}}
          package.preload["runtime.configuration"] = function()
            loads = loads + 1
            return {streams = streams}
          end
          package.preload["presentation.availability"] = function()
            return {
              rows = function(active_mods, selected_target, force, query, supplied_streams)
                rows_calls = rows_calls + 1
                assert(supplied_streams == streams and supplied_streams.research_material_lead.enabled == false)
                return {}
              end
            }
          end
          package.loaded["runtime.configuration"] = nil
          package.loaded["presentation.availability"] = nil
          boot()

          local root = library.open(player, {tab = "availability"})
          local query = research_filters(root)["mir_library_query"]
          query.text = "lead"
          library.on_gui_text_changed({player_index = 1, element = query})
          assert(loads == 1 and rows_calls >= 2,
            "Availability must reuse one parse-time effective configuration across refreshes")
        ''')

    def test_default_closed_then_query_selection_location_native_navigation_and_reload_rebuild(self):
        self.lua.execute('''
          boot()
          library.on_init(); library.on_configuration_changed(); library.on_load()
          assert(next(storage) == nil and library.subscription_needs() == false)
          library.on_lua_shortcut({prototype_name = "mir-research-browser", player_index = 1})
          local root = player.gui.screen["mir_research_browser"]
          assert(root and player.shortcut_name == "mir-research-browser" and player.shortcut_toggled)
          assert(storage.mir_library.schema == 1 and storage.mir_library.players[1].query == ""
            and storage.mir_library.players[1].status == 1)
          library.on_gui_location_changed({player_index = 1, element = root,})
          root.location = {x = 91, y = 44}
          library.on_gui_location_changed({player_index = 1, element = root})
          local original_root = root
          local query = research_filters(root)["mir_library_query"]
          local original_query = query
          query.text = "gear"
          library.on_gui_text_changed({player_index = 1, element = query})
          root = player.gui.screen["mir_research_browser"]
          assert(root == original_root and research_filters(root)["mir_library_query"] == original_query)
          query.text = "gear wheel"
          library.on_gui_text_changed({player_index = 1, element = query})
          root = player.gui.screen["mir_research_browser"]
          assert(root == original_root and research_filters(root)["mir_library_query"] == original_query)
          local rows = research_content(root)["mir_library_list_pane"]["mir_library_results"]
          assert(#rows.items == 1 and rows.items[1][3] == "Iron gear wheel productivity")
          rows.selected_index = 1
          library.on_gui_selection_state_changed({player_index = 1, element = rows})
          root = player.gui.screen["mir_research_browser"]
          local state = storage.mir_library.players[1]
          assert(state.query == "gear wheel" and state.selected == gear.name and state.scroll == 1)
          assert(research_content(root)["mir_library_list_pane"]["mir_library_actions"]["mir_library_open_native"].sprite
            == "utility/side_menu_technology_icon")
          assert(state.location.x == 91 and state.location.y == 44)
          local before = storage.mir_library
          library.on_load()
          assert(storage.mir_library == before)
          library.on_gui_click({player_index = 1, element = research_content(root)["mir_library_list_pane"]["mir_library_actions"]["mir_library_open_native"]})
          assert(player.opened_technology == gear and player.gui.screen["mir_research_browser"] == nil)
          assert(not player.shortcut_toggled)
          library.open(player)
          root = player.gui.screen["mir_research_browser"]
          assert(root.location.x == 91 and root.location.y == 44)
          assert(research_content(root)["mir_library_list_pane"]["mir_library_results"].scrolled_to.index == 1)
          library.on_gui_click({player_index = 1, element = research_content(root)["mir_library_list_pane"]["mir_library_actions"]["mir_library_close"]})
          assert(player.gui.screen["mir_research_browser"] == nil and not player.shortcut_toggled)
        ''')

    def test_filters_and_foreign_events_are_bounded(self):
        self.lua.execute('''
          boot()
          library.on_gui_text_changed({player_index = 1, element = {valid = true, name = "foreign", text = "nope"}})
          assert(next(storage) == nil)
          library.open(player)
          local root = player.gui.screen["mir_research_browser"]
          local family = research_filters(root)["mir_library_filter_grid"]["mir_library_family_field"]["mir_library_family"]
          family.selected_index = 2
          library.on_gui_selection_state_changed({player_index = 1, element = family})
          root = player.gui.screen["mir_research_browser"]
          assert(#research_content(root)["mir_library_list_pane"]["mir_library_results"].items == 1)
          library.on_player_removed({player_index = 1})
          assert(storage.mir_library.players[1] == nil)
        ''')

    def test_pre_player_removal_destroys_only_the_owned_library_before_player_state_is_retired(self):
        self.lua.execute('''
          boot()
          local root = library.open(player, {query = "gear"})
          assert(root.valid and storage.mir_library.players[1].open == true)
          library.on_pre_player_removed({player_index = 1})
          assert(not root.valid and player.gui.screen["mir_research_browser"] == nil,
            "the owned Library root must be destroyed while its player is still available")
          assert(storage.mir_library.players[1].open == false,
            "pre-removal must close the persisted view before the post-removal cleanup")
          library.on_player_removed({player_index = 1})
          assert(storage.mir_library.players[1] == nil,
            "post-removal must retire the removed player's Library state")
        ''')

    def test_completed_or_closed_player_keeps_peer_translation_maintenance_until_its_reply(self):
        self.lua.execute(r'''
          for _,order in ipairs({"reply-first","close-first"}) do
            boot()
            local peer={valid=true,index=2,name="Bob",locale="de",connected=true,force=player.force,
              gui={screen=gui_container(nil)},display_resolution=player.display_resolution,display_scale=1,
              translation_requests={}}
            peer.request_translation=function(payload)
              peer.translation_requests[#peer.translation_requests+1]={id=202,localised=payload}
              return 202
            end
            player.request_translation=function(payload)
              player.translation_requests[#player.translation_requests+1]={id=101,localised=payload}
              return 101
            end
            game.get_player=function(index)return index==1 and player or index==2 and peer or nil end
            route_native_events(false,false,{on_string_translated=14})
            local open=remote.interfaces["more-infinite-research-browser"].open
            assert(open(1) and open(2))
            local first=player.gui.screen.mir_research_browser
            local second=peer.gui.screen.mir_research_browser
            local query=research_filters(second).mir_library_query
            local queue,current,progress=player.force.research_queue,player.force.current_research,player.force.research_progress
            local ledger=storage.mir_library.translations
            local peer_cache=ledger.working[2].cache
            local peer_pending=ledger.active[2].pending[1]
            assert(peer_pending.request_id==202 and #player.translation_requests==1
              and #peer.translation_requests==1)
            local reply=native_handlers.events[14]
            local close=native_handlers.events[defines.events.on_gui_closed]
            local function first_reply()
              reply{player_index=1,id=101,translated=true,result="First player caption"}
            end
            local function first_close()
              close{player_index=1,element=first}
            end
            if order=="reply-first" then first_reply();first_close()
            else first_close();first_reply() end

            assert(library.subscription_needs() and native_ticks[library.translation_maintenance_ticks]~=nil,
              "another player's issued translation must keep actual maintenance registered")
            assert(not first.valid and player.gui.screen.mir_research_browser==nil
              and ledger.active[1]==nil and ledger.working[1]==nil)
            assert(second.valid and peer.gui.screen.mir_research_browser==second
              and query==research_filters(second).mir_library_query and query.text=="",
              "completion/close replaced or edited the peer's owned view")
            assert(ledger.working[2].cache==peer_cache and ledger.active[2].pending[1].request_id==202
              and peer_cache.labels[gear.name]==nil and #peer.translation_requests==1,
              "completion/close consumed or relabelled the peer's issued work")
            reply{player_index=2,id=202,translated=true,result="Zahnrad des zweiten Spielers"}
            assert(not library.subscription_needs() and native_ticks[library.translation_maintenance_ticks]==nil,
              "the final peer callback must remove translation maintenance")
            assert(ledger.active[2]==nil and peer_cache.labels[gear.name]=="Zahnrad des zweiten Spielers")
            assert(research_content(second).mir_library_list_pane.mir_library_results.items[1][3]=="Zahnrad des zweiten Spielers"
              and second==peer.gui.screen.mir_research_browser and query==research_filters(second).mir_library_query)
            assert(player.force.research_queue==queue and player.force.current_research==current
              and player.force.research_progress==progress and gear.level==3 and gear.enabled==false)
          end
        ''')

    def test_translation_dispatch_is_open_connected_only_and_closed_callbacks_only_release(self):
        self.lua.execute('''
          boot()
          player.connected = false
          library.open(player)
          assert(#player.translation_requests == 0 and next(storage) == nil and library.subscription_needs() == false)
          library.close(player)

          player.connected = true
          library.open(player)
          assert(#player.translation_requests == 1 and library.subscription_needs())
          local gear_request = player.translation_requests[1].id
          library.close(player)
          assert(player.gui.screen["mir_research_browser"] == nil)
          library.on_translation_maintenance({tick = 1})
          assert(#player.translation_requests == 1 and library.subscription_needs())
          library.on_string_translated({player_index = 1, id = gear_request,
            translated = true, result = "Closed stale gear"})
          assert(library.subscription_needs() == false)
        ''')

    def test_base_literal_translation_names_reach_the_real_library_list_and_detail(self):
        self.lua.execute(r'''
          -- Factorio 2.1.23 Base has no item-name.electric-mining-drill.  The
          -- old emitted child therefore makes this native-like request double
          -- refuse eagerly before it can publish a Library label.
          local locale = {
            ["technology-name.more-infinite-research.research_mining_drill"] = "Erzförderer-Produktivität",
            ["technology-name.more-infinite-research.research_gears"] = "Eisenrad-Produktivität",
            ["item-name.iron-gear-wheel"] = "Eisenrad"
          }
          local function translate(value)
            if type(value) == "string" then
              if locale[value] ~= nil then return locale[value] end
              if string.find(value, "%-name%.") then
                error("unresolved F210 Base locale key: " .. value)
              end
              return value
            end
            assert(type(value) == "table" and type(value[1]) == "string", "invalid LocalisedString")
            local key = value[1]
            if key == "" then
              local parts = {}
              for index = 2, #value do parts[#parts + 1] = translate(value[index]) end
              return table.concat(parts)
            elseif key == "?" then
              for index = 2, #value do
                local ok, result = pcall(translate, value[index])
                if ok and result ~= "" then return result end
              end
              return ""
            end
            local text = assert(locale[key], "unresolved F210 Base locale key: " .. tostring(key))
            for index = 2, #value do
              local replacement = translate(value[index])
              text = string.gsub(text, "__" .. tostring(index - 1) .. "__", function() return replacement end)
            end
            return text
          end
          local old_shape = {
            "technology-name.more-infinite-research.research_mining_drill",
            {"item-name.electric-mining-drill"}
          }
          local old_ok, old_error = pcall(translate, old_shape)
          assert(not old_ok and string.find(old_error, "item-name.electric-mining-drill", 1, true),
            "the old unresolved child did not fail the native-like translator")

          -- Use the actual Base catalogue and data-stage constructor, then
          -- feed that emitted LocalisedString to the unmocked Library model.
          local modern_catalogue = require("compatibility.modern_catalogue")
          local definition
          for _, candidate in ipairs(modern_catalogue.select({}).definitions) do
            if candidate.key == "research_mining_drill" then definition = candidate; break end
          end
          assert(definition)
          local stream = {base_cost=8000, linear_increment=0, growth_factor=2,
            effect_percent=20, research_time=60, enabled=true}
          local emitted = require("research.modern").technology(definition,
            {options={}, streams={[definition.family]=stream}})
          assert(emitted.name == "recipe-prod-research_mining_drill-1"
            and #emitted.localised_name == 1
            and emitted.localised_name[1] == "technology-name.more-infinite-research.research_mining_drill")

          local gear_emitted = require("research.productivity").gears(stream)
          assert(gear_emitted.localised_name[2][1] == "item-name.iron-gear-wheel")
          package.preload["presentation.library_model"] = nil
          package.loaded["presentation.library_model"] = nil
          boot()
          local mining = {valid=true, name=emitted.name, level=1, researched=false, enabled=true,
            visible_when_disabled=true, localised_name=emitted.localised_name,
            prototype={max_level=4294967295, effects=emitted.effects}}
          gear = {valid=true, name=gear_emitted.name, level=1, researched=false, enabled=true,
            visible_when_disabled=true, localised_name=gear_emitted.localised_name,
            prototype={max_level=4294967295, effects=gear_emitted.effects}}
          player.force.technologies = {[mining.name]=mining, [gear.name]=gear}
          player.force.research_queue, player.force.current_research, player.force.research_progress = {},nil,0
          library_declarations = {
            {id=mining.name, family=definition.family, progression=1, native_order=definition.order,
              setting="ips-enable-" .. definition.family, cap_setting="ips-max-level-" .. definition.family,
              recipe="burner-mining-drill", locale_key=emitted.localised_name[1]},
            {id=gear.name, family="research_gears", progression=1, native_order="p[research_gears]",
              setting="ips-enable-research_gears", cap_setting="ips-max-level-research_gears",
              recipe="iron-gear-wheel", locale_key=gear_emitted.localised_name[1]}
          }
          player.request_translation = function(localised)
            local request = {id=player.next_translation_id + 1, localised=localised, result=translate(localised)}
            player.next_translation_id = request.id
            player.translation_requests[#player.translation_requests + 1] = request
            return request.id
          end
          local root = library.open(player, {selected=mining.name})
          assert(#player.translation_requests == 2)
          for _, request in ipairs(player.translation_requests) do
            library.on_string_translated({player_index=1, id=request.id, translated=true, result=request.result})
          end
          local content = research_content(root)
          local listed = content["mir_library_list_pane"]["mir_library_results"].items
          assert(#listed == 2 and (listed[1][3] == "Erzförderer-Produktivität" or listed[2][3] == "Erzförderer-Produktivität"))
          assert(listed[1][3] == "Eisenrad-Produktivität" or listed[2][3] == "Eisenrad-Produktivität",
            "the working gear LocalisedString regressed")
          assert(content["mir_library_detail"].mir_library_research_facts.mir_library_detail_heading["mir_library_detail_title"].caption == "Erzförderer-Produktivität")
        ''')

    def test_imported_finite_cap_keeps_zero_default_and_direct_provenance(self):
        # Accepted zero/direct/effective case from historical portable-core
        # blob 55be2847fae29855efac6a294887012827013eef.
        self.lua.execute(r'''
          package.preload["presentation.library_model"] = nil
          package.loaded["presentation.library_model"] = nil
          boot()
          local catalog = require("research.settings")
          local name = "ips-max-level-research_gears"
          assert(catalog.spec(name).default_value == 0)
          helpers = {encode_string=function(value) return value end,
            decode_string=function(value) return value end,
            json_to_table=function(value)
              assert(value == "finite-cap-profile")
              return {schema=1, kind="mir-settings-profile", settings={[name]=10}}
            end}
          settings.startup[name] = {value=0}
          settings.startup[catalog.import_setting_name] = {value="MIRSET1:finite-cap-profile"}
          local effective = catalog.effective_values(settings.startup, helpers)
          assert(effective[name] == 10, "valid zero direct/default cap blocked a finite imported value")
          library.set_cap_provider(function(force)
            assert(force == player.force)
            return {[gear.name]=effective[name]}
          end)
          local root = library.open(player, {selected=gear.name})
          local cap = research_content(root)["mir_library_detail"].mir_library_research_facts["mir_library_detail_cap"]
          assert(cap.caption[1] == "mir-browser.cap-finite" and cap.caption[2] == 10)
          library.open(player, {tab="settings", settings_scope="research", settings_search="research_gears"})
          local detail = root["mir_library_tabs"]["mir_library_settings_content"]
            ["mir_library_settings_dynamic"]["mir_library_settings_detail"]
          local value = detail.mir_library_settings_fields["mir_library_setting_" .. catalog.spec(name).field_index .. "_value"]
          assert(value.caption[1]=="mir-browser.setting-with-default" and value.caption[2] == "10"
            and value.tooltip[2][1] == "mir-browser.setting-unlimited"
            and value.tooltip[3][1] == "mir-browser.setting-unlimited"
            and value.tooltip[4][1] == "mir-browser.source-mirset1",
            "finite imported cap lost its valid zero default/direct provenance")
          assert(settings.startup[name].value == 0 and gear.level == 3 and gear.researched and not gear.enabled)
        ''')

    def test_full_translation_callback_keeps_late_recipe_item_and_fluid_search_terms(self):
        # v4.7.3 research_browser_native_discovery_regressions.lua rejects the
        # original 1 KiB callback truncation; this is host coverage, not native input.
        self.lua.execute(r'''
          package.preload["presentation.library_model"] = nil
          package.loaded["presentation.library_model"] = nil
          boot()
          player.locale = "de"
          gear.localised_name = "Produktivitätsforschung"
          gear.prototype.effects = {{type="unlock-recipe", recipe="broad-recipe"}}
          prototypes = {
            recipe = {["broad-recipe"] = {
              localised_name=string.rep("Langes Rezept ", 100) .. "recipe-tail",
              products={{type="item", name="broad-item"}, {type="fluid", name="broad-fluid"}}
            }},
            item = {["broad-item"] = {localised_name="item-tail"}},
            fluid = {["broad-fluid"] = {localised_name="fluid-tail"}}
          }
          local function translated(value)
            if type(value) == "string" then return value end
            assert(type(value) == "table")
            if value[1] == "?" then return translated(value[2]) end
            assert(value[1] == "")
            local parts = {}
            for index=2,#value do parts[#parts+1] = translated(value[index]) end
            return table.concat(parts)
          end
          local native_queue, current = player.force.research_queue, player.force.current_research
          local root = library.open(player, {query="item-tail", selected=gear.name})
          local query = research_filters(root)["mir_library_query"]
          local request = player.translation_requests[1]
          assert(#player.translation_requests == 1)
          local payload = translated(request.localised)
          for _, term in ipairs({"recipe-tail", "item-tail", "fluid-tail"}) do
            assert(string.find(payload, term, 1, true) > 1024)
          end
          assert(#research_content(root)["mir_library_list_pane"]["mir_library_results"].items == 0)
          library.on_string_translated({player_index=1, id=request.id+999, translated=true, result=payload})
          assert(#research_content(root)["mir_library_list_pane"]["mir_library_results"].items == 0,
            "an unrelated callback published localized search data")
          library.on_string_translated({player_index=1, id=request.id, translated=true, result=payload})
          for _, term in ipairs({"recipe-tail", "item-tail", "fluid-tail"}) do
            query.text = term
            library.on_gui_text_changed({player_index=1, element=query})
            local listed = research_content(root)["mir_library_list_pane"]["mir_library_results"].items
            assert(#listed == 1 and listed[1][3] == "Produktivitätsforschung",
              "a late recipe/item/fluid term was lost through callback or refresh: " .. term)
            assert(player.gui.screen["mir_research_browser"] == root and root.valid
              and research_filters(root)["mir_library_query"] == query,
              "localized search rebuilt the owned window or query control")
          end
          assert(player.force.research_queue == native_queue and player.force.current_research == current
            and gear.level == 3 and gear.researched and not gear.enabled,
            "localized search changed native research state")
        ''')

    def test_all_view_scans_native_identities_once_and_family_change_invalidates_unissued_work(self):
        self.lua.execute('''
          boot()
          library.open(player)
          assert(#player.translation_requests == 1
            and player.translation_requests[1].localised == "Iron gear wheel productivity")
          local root = player.gui.screen["mir_research_browser"]
          local query = research_filters(root)["mir_library_query"]
          query.text = "gear"
          library.on_gui_text_changed({player_index = 1, element = query})
          assert(#player.translation_requests == 1)

          local family = research_filters(root)["mir_library_filter_grid"]["mir_library_family_field"]["mir_library_family"]
          family.selected_index = 2
          library.on_gui_selection_state_changed({player_index = 1, element = family})
          -- The first request remains a stale issued window; the all-family
          -- cache requests its current MIR row and actual foreign native row.
          assert(#player.translation_requests == 3)
          local old_id = player.translation_requests[1].id
          local all_gear = player.translation_requests[2].id
          local all_foreign = player.translation_requests[3].id
          library.on_string_translated({player_index = 1, id = old_id,
            translated = true, result = "old label"})
          library.on_string_translated({player_index = 1, id = all_gear,
            translated = true, result = "Gear translated"})
          library.on_string_translated({player_index = 1, id = all_foreign,
            translated = true, result = "Foreign translated"})
          root = player.gui.screen["mir_research_browser"]
          assert(research_content(root)["mir_library_list_pane"]["mir_library_results"].items[1][3] == "Gear translated")
        ''')

    def test_private_credit_holders_stay_out_of_library_selection_translation_and_native_open(self):
        self.lua.execute(r'''
          package.preload["presentation.library_model"] = nil
          package.loaded["presentation.library_model"] = nil
          local credits = {
            "mir-legacy-module-credit-speed-module",
            "mir-legacy-module-credit-productivity-module",
            "mir-legacy-module-credit-efficiency-module",
            "mir-legacy-cannon-credit-rocket-shooting-speed",
            "mir-native-credit-research_electric_shooting_speed-electric-positive",
            "zz-mir-native-credit-research_electric_shooting_speed-electric-negative",
            "mir-native-credit-research_electric_shooting_speed-tesla-positive",
            "zz-mir-native-credit-research_electric_shooting_speed-tesla-negative"
          }
          library_private_credit_ids = {}
          for _, id in ipairs(credits) do library_private_credit_ids[id] = true end
          boot()

          for index, id in ipairs(credits) do
            player.force.technologies[id] = {
              valid = true, name = id, level = index + 1, researched = true,
              enabled = false, visible_when_disabled = false, localised_name = "Private credit " .. index,
              prototype = {max_level = 4294967295}
            }
          end
          local original_queue = {credits[1], foreign.name, credits[2], gear.name, credits[3], credits[4]}
          player.force.research_queue, player.force.current_research, player.force.research_progress =
            original_queue, credits[1], .42
          local before_queue = {}
          for index, id in ipairs(original_queue) do before_queue[index] = id end
          local before_current, before_progress = player.force.current_research, player.force.research_progress

          local function assert_private_rows(root, label)
            local listed = {}
            for _, item in ipairs(research_content(root)["mir_library_list_pane"]["mir_library_results"].items) do listed[item[3]] = true end
            assert(listed[gear.localised_name] and listed[foreign.localised_name], label .. " dropped ordinary rows")
            for index, id in ipairs(credits) do
              assert(not listed[id] and not listed["Private credit " .. index], label .. " exposed private credit: " .. id)
            end
          end

          local root = library.open(player, {family = "all", selected = foreign.name})
          local view = storage.mir_library.players[1]
          assert(view.selected == foreign.name, "ordinary foreign selection was not retained")
          assert_private_rows(root, "no cap provider")
          assert(#player.translation_requests == 2,
            "private credit received a translation request")
          for _, request in ipairs(player.translation_requests) do
            for index = 1, #credits do
              assert(request.localised ~= "Private credit " .. index,
                "private credit translation was dispatched")
            end
          end

          library.set_cap_provider(function() error("unavailable cap provider") end)
          root = library.open(player)
          assert_private_rows(root, "failing cap provider")
          library.set_cap_provider(function() return "malformed caps" end)
          root = library.open(player)
          assert_private_rows(root, "malformed cap provider")
          library.set_cap_provider(function(force)
            assert(force == player.force)
            return {}
          end)
          root = library.open(player)
          assert_private_rows(root, "successful cap provider")

          library.open(player, {hidden = {foreign.name}})
          library.open(player, {selected = credits[1], hidden = {credits[2]}})
          view = storage.mir_library.players[1]
          assert(view.selected == foreign.name and view.hidden[foreign.name] == true
            and view.hidden[credits[2]] == nil,
            "private remote selection or hidden input replaced retained foreign state")

          root = library.open(player, {tab = "queue"})
          local queue_items = root["mir_library_tabs"]["mir_library_queue_content"]["mir_library_queue_list"].items
          assert(#queue_items == 2 and queue_items[1][3] == foreign.localised_name
            and queue_items[2][3] == gear.localised_name,
            "queue projection exposed private credit or changed ordinary native order")

          library.close(player)
          storage.mir_library.players[1].selected = credits[1]
          root = library.open(player, {tab = "research"})
          local actions = research_content(root)["mir_library_list_pane"]["mir_library_actions"]
          assert(storage.mir_library.players[1].selected == credits[1]
            and actions["mir_library_open_native"].enabled == false,
            "stale private selection was repaired or exposed as an openable row")
          library.on_gui_click({player_index = 1, element = actions["mir_library_open_native"]})
          assert(player.gui.screen["mir_research_browser"] == root and player.opened_technology == nil,
            "stale private selection opened native research or closed the Library")

          assert(player.force.research_queue == original_queue and #player.force.research_queue == #before_queue
            and player.force.current_research == before_current and player.force.research_progress == before_progress)
          for index, id in ipairs(before_queue) do
            assert(player.force.research_queue[index] == id, "Library changed native queue order")
          end
          for index, id in ipairs(credits) do
            local holder = player.force.technologies[id]
            assert(holder.level == index + 1 and holder.researched == true and holder.enabled == false,
              "Library changed private credit state")
          end
        ''')

    def test_all_view_native_translation_scan_is_bounded_before_request_dispatch(self):
        self.lua.execute('''
          boot()
          for index = 1, 30001 do
            local id = "native-" .. index
            player.force.technologies[id] = {valid = true, name = id, localised_name = id}
          end
          library.open(player, {family = "all"})
          assert(#player.translation_requests == 0 and library.subscription_needs() == false)
        ''')
    def test_translation_callback_checks_live_scope_and_discards_vanished_root(self):
        self.lua.execute('''
          boot()
          library.open(player)
          local id = player.translation_requests[1].id
          local root = player.gui.screen["mir_research_browser"]
          player.locale = "de"
          -- Native state may lead its locale-change event. The response frees
          -- the ID without applying the label to the stale cached scope.
          library.on_string_translated({player_index = 1, id = id,
            translated = true, result = "incorrect locale label"})
          assert(research_content(root)["mir_library_list_pane"]["mir_library_results"].items[1][3] == "Iron gear wheel productivity")
          assert(library.subscription_needs() == false)
          library.on_player_locale_changed({player_index = 1})
          assert(#player.translation_requests == 2)

          local locale_current = player.translation_requests[2].id
          player.force.index = 2
          library.on_string_translated({player_index = 1, id = locale_current,
            translated = true, result = "incorrect force label"})
          assert(research_content(root)["mir_library_list_pane"]["mir_library_results"].items[1][3] == "Iron gear wheel productivity")
          library.on_player_changed_force({player_index = 1})
          assert(#player.translation_requests == 3)

          local current = player.translation_requests[3].id
          root = player.gui.screen["mir_research_browser"]
          root.destroy()
          library.on_string_translated({player_index = 1, id = current,
            translated = true, result = "rootless label"})
          local view = storage.mir_library.players[1]
          local open, pending = library.native_subscription_needs()
          assert(player.gui.screen["mir_research_browser"] == nil and library.subscription_needs() == false)
          assert(view.open == false and view.refresh_pending == false and not open and not pending,
            "late rootless callback retained a native Library subscription")
        ''')

    def test_vanished_root_locale_and_force_invalidations_retire_native_view_flags(self):
        self.lua.execute('''
          boot()
          library.open(player)
          local root = player.gui.screen["mir_research_browser"]
          root.destroy()
          library.on_player_locale_changed({player_index = 1})
          library.on_player_changed_force({player_index = 1})
          local view = storage.mir_library.players[1]
          local open, pending = library.native_subscription_needs()
          assert(view.open == false and view.refresh_pending == false and not open and not pending,
            "rootless locale or force invalidation retained a native Library subscription")
          assert(#player.translation_requests == 1 and library.subscription_needs(),
            "invalidating a vanished root released its durable native request")
        ''')

    def test_malformed_translation_sidecar_and_active_window_are_preserved_without_new_requests(self):
        self.lua.execute('''
          boot()
          local unknown = {version = "future", retained = {request = 99}}
          storage.mir_library = {schema = 1, players = {}, translations = unknown}
          library.open(player)
          assert(storage.mir_library.translations == unknown and #player.translation_requests == 0)

          boot()
          local malformed = {pending = {{request_id = "not-a-native-id"}}}
          local ledger = {schema = 1, next_epoch = 0, active = {[1] = malformed}, retired = {}}
          storage.mir_library = {schema = 1, players = {}, translations = ledger}
          library.open(player)
          assert(storage.mir_library.translations == ledger and ledger.active[1] == malformed)
          assert(#player.translation_requests == 0)
          library.on_translation_maintenance({tick = 1800})
          assert(ledger.active[1] == malformed and #player.translation_requests == 0)
        ''')
    def test_pending_translations_survive_locale_change_close_and_reload(self):
        self.lua.execute('''
          boot()
          library.open(player, {family = "all"})
          assert(#player.translation_requests == 2)
          player.locale = "de"
          library.on_player_locale_changed({player_index = 1})
          assert(#player.translation_requests == 4)
          local pending = storage.mir_library.translations.active[1].pending
          assert(#pending == 4)
          local queue, current, progress = player.force.research_queue,
            player.force.current_research, player.force.research_progress
          library.close(player)
          assert(storage.mir_library.translations.working == nil)
          package.loaded["runtime.library"] = nil
          library = require("runtime.library")
          library.on_load()
          library.open(player, {family = "all"})
          assert(#player.translation_requests == 6,
            "valid old/current translation requests prevented a reopened Library from dispatching")
          for index = 1, 4 do
            library.on_string_translated({player_index = 1,
              id = player.translation_requests[index].id, translated = true, result = "STALE"})
          end
          library.on_string_translated({player_index = 1, id = player.translation_requests[5].id,
            translated = true, result = "Zahnrad"})
          library.on_string_translated({player_index = 1, id = player.translation_requests[6].id,
            translated = true, result = "Fremde Forschung"})
          local root = player.gui.screen["mir_research_browser"]
          assert(research_content(root)["mir_library_list_pane"]["mir_library_results"].items[1][3] == "Zahnrad")
          assert(not library.subscription_needs())
          assert(player.force.research_queue == queue and player.force.current_research == current
            and player.force.research_progress == progress)
        ''')

    def test_warm_and_cold_translation_replies_produce_equal_saved_work_and_native_requests(self):
        self.lua.execute(r'''
          boot()
          for index=1,18 do
            local name="foreign-cold-probe-"..index
            player.force.technologies[name]={valid=true,name=name,level=1,researched=false,
              enabled=true,visible_when_disabled=false,localised_name=name,prototype={max_level=1}}
          end
          library.open(player,{family="all"})
          assert(#player.translation_requests==16)
          local function clone(value)
            if type(value)~="table" then return value end
            local copied={}; for key,child in pairs(value) do copied[key]=clone(child) end
            return copied
          end
          local function equal(left,right)
            if type(left)~=type(right) then return false end
            if type(left)~="table" then return left==right end
            for key,value in pairs(left) do if not equal(value,right[key]) then return false end end
            for key in pairs(right) do if left[key]==nil then return false end end
            return true
          end
          local before,requests,warm=clone(storage),clone(player.translation_requests),library
          package.loaded["runtime.library"]=nil
          local cold=require("runtime.library")
          local function reply(module)
            for index=1,8 do
              module.on_string_translated{player_index=1,id=requests[index].id,
                translated=true,result="translated-"..index}
            end
          end
          player.translation_requests={}
          reply(warm)
          local warm_state,warm_requests=clone(storage),clone(player.translation_requests)
          storage=clone(before)
          player.translation_requests={}; player.next_translation_id=16
          local available_game=game
          game=nil
          cold.on_load()
          assert(equal(storage,before),"on_load changed saved translation work")
          game=available_game
          reply(cold)
          assert(equal(storage,warm_state),"cache warmth changed durable translation work")
          assert(equal(player.translation_requests,warm_requests),"cache warmth changed native requests")
          assert(#player.translation_requests==4 and #storage.mir_library.translations.active[1].pending==12)
        ''')

    def test_completed_open_translation_work_survives_load_and_is_retired_on_close(self):
        self.lua.execute(r'''
          boot()
          local root=library.open(player,{family="all"})
          for index=1,2 do
            library.on_string_translated{player_index=1,id=player.translation_requests[index].id,
              translated=true,result=index==1 and "Zahnrad" or "Fremde Forschung"}
          end
          assert(not library.subscription_needs())
          local ledger=storage.mir_library.translations
          local saved_cache=ledger.working[1].cache
          local epoch=ledger.next_epoch
          package.loaded["runtime.library"]=nil
          library=require("runtime.library")
          local available_game=game; game=nil
          library.on_load()
          assert(ledger.working[1].cache==saved_cache and ledger.next_epoch==epoch)
          game=available_game
          assert(library.open(player)==root and #player.translation_requests==2 and ledger.next_epoch==epoch)
          assert(research_content(root)["mir_library_list_pane"]["mir_library_results"].items[1][3]=="Zahnrad")
          library.close(player)
          assert(ledger.working==nil and ledger.active[1]==nil and not library.subscription_needs())
        ''')

    def test_issued_only_legacy_translation_sidecar_loads_read_only_and_drains_without_reissue(self):
        self.lua.execute(r'''
          boot()
          library.open(player,{family="all"})
          local ledger=storage.mir_library.translations
          -- Pre-correction MIR5 saved only issued IDs, without a working map.
          ledger.working=nil
          local pending=ledger.active[1].pending
          package.loaded["runtime.library"]=nil
          library=require("runtime.library")
          local available_game=game; game=nil
          library.on_load()
          assert(ledger.working==nil and ledger.active[1].pending==pending)
          game=available_game
          for index=1,2 do
            library.on_string_translated{player_index=1,id=player.translation_requests[index].id,
              translated=true,result="old-window"}
          end
          assert(ledger.working==nil and not library.subscription_needs() and #player.translation_requests==2)
          library.open(player,{family="all"})
          assert(#player.translation_requests==4 and ledger.working[1].schema==1)
        ''')

    def test_translation_maintenance_orders_open_players_before_issuing_native_retries(self):
        self.lua.execute(r'''
          boot()
          local order,next_id={},100
          player.request_translation=function() order[#order+1]=1;next_id=next_id+1;return next_id end
          local second={valid=true,index=2,locale="de",connected=true,force=player.force,
            gui={screen=gui_container(nil)},set_shortcut_toggled=function() end,
            request_translation=function() order[#order+1]=2;next_id=next_id+1;return next_id end}
          game.get_player=function(index) return index==1 and player or index==2 and second or nil end
          library.open(player,{family="all"}); library.open(second,{family="all"})
          setmetatable(storage.mir_library.translations.active,{__pairs=function(rows)
            local index=3
            return function() index=index-1;if index>0 then return index,rows[index] end end
          end})
          order={}
          library.on_translation_maintenance{tick=1800}
          assert(table.concat(order,",")=="1,1,2,2","native request order follows active-map traversal")
        ''')

    def test_configuration_invalidates_a_saved_open_working_cache_without_prior_on_load(self):
        self.lua.execute(r'''
          boot()
          library.open(player,{family="all"})
          for index=1,2 do
            library.on_string_translated{player_index=1,id=player.translation_requests[index].id,
              translated=true,result="old-configuration"}
          end
          local ledger=storage.mir_library.translations
          local old_cache,epoch=ledger.working[1].cache,ledger.next_epoch
          package.loaded["runtime.library"]=nil
          library=require("runtime.library")
          library.on_configuration_changed()
          assert(ledger.working[1].cache~=old_cache and ledger.next_epoch>epoch)
          assert(#player.translation_requests==4)
          assert(research_content(player.gui.screen["mir_research_browser"])["mir_library_list_pane"]["mir_library_results"].items[1][3]
            =="Iron gear wheel productivity","configuration retained old translated labels")
        ''')

    def test_unknown_saved_translation_work_is_preserved_and_cannot_issue_another_window(self):
        self.lua.execute(r'''
          boot()
          library.open(player,{family="all"})
          local ledger=storage.mir_library.translations
          local unknown={schema=77,cache={pending={99}}}
          ledger.working[1]=unknown
          package.loaded["runtime.library"]=nil
          library=require("runtime.library")
          library.on_load()
          library.open(player,{family="all"})
          assert(ledger.working[1]==unknown and #player.translation_requests==2)
          library.close(player)
          assert(ledger.working[1]==unknown and library.subscription_needs())
        ''')

    def test_translation_stale_scope_reload_and_reused_index_never_publish_old_labels(self):
        self.lua.execute('''
          boot()
          library.open(player, {family = "all"})
          local old_gear = player.translation_requests[1].id
          local old_foreign = player.translation_requests[2].id
          player.locale = "de"
          library.on_player_locale_changed({player_index = 1})
          assert(#player.translation_requests == 4)
          local locale_gear = player.translation_requests[3].id
          local locale_foreign = player.translation_requests[4].id
          library.on_string_translated({player_index = 1, id = old_gear,
            translated = true, result = "OLD GEAR"})
          library.on_string_translated({player_index = 1, id = old_foreign,
            translated = true, result = "OLD FOREIGN"})
          local root = player.gui.screen["mir_research_browser"]
          assert(research_content(root)["mir_library_list_pane"]["mir_library_results"].items[1][3] == "Iron gear wheel productivity")

          player.force.index = 2
          library.on_player_changed_force({player_index = 1})
          assert(#player.translation_requests == 6)
          local force_gear = player.translation_requests[5].id
          local force_foreign = player.translation_requests[6].id
          library.on_string_translated({player_index = 1, id = locale_gear,
            translated = true, result = "STALE LOCALE GEAR"})
          library.on_string_translated({player_index = 1, id = locale_foreign,
            translated = true, result = "STALE LOCALE FOREIGN"})
          root = player.gui.screen["mir_research_browser"]
          assert(research_content(root)["mir_library_list_pane"]["mir_library_results"].items[1][3] == "Iron gear wheel productivity")
          library.on_string_translated({player_index = 1, id = force_gear,
            translated = true, result = "Zahnrad"})
          library.on_string_translated({player_index = 1, id = force_foreign,
            translated = true, result = "Fremde Forschung"})
          root = player.gui.screen["mir_research_browser"]
          assert(research_content(root)["mir_library_list_pane"]["mir_library_results"].items[1][3] == "Zahnrad")

          local saved = storage.mir_library
          local reload_gear, reload_foreign = force_gear, force_foreign
          library.close(player)
          library.open(player)
          reload_gear, reload_foreign = player.translation_requests[7].id, player.translation_requests[8].id
          package.loaded["runtime.library"] = nil
          library = require("runtime.library")
          library.on_load()
          assert(storage.mir_library == saved and library.subscription_needs())
          library.on_string_translated({player_index = 1, id = reload_gear,
            translated = true, result = "late"})
          library.on_string_translated({player_index = 1, id = reload_foreign,
            translated = true, result = "late"})
          assert(library.subscription_needs() == false)

          assert(#player.translation_requests == 8
            and research_content(player.gui.screen["mir_research_browser"])["mir_library_list_pane"]["mir_library_results"].items[1][3] == "late",
            "same-scope callbacks were not restored consistently across load")
          -- A later explicit close/open starts the separate request lifetime
          -- used by the removed/reused-player regression below.
          library.close(player)
          library.open(player)
          local removed_gear, removed_foreign = player.translation_requests[9].id, player.translation_requests[10].id
          library.on_player_removed({player_index = 1})
          assert(storage.mir_library.players[1] == nil and library.subscription_needs())

          local prior_requests = #player.translation_requests
          screen = gui_container(nil)
          player = {
            valid = true, index = 1, locale = "en", connected = true, gui = {screen = screen},
            force = {index = 1, technologies = {[gear.name] = gear, [foreign.name] = foreign},
              research_queue = {}, current_research = nil},
            translation_requests = {}, next_translation_id = 100
          }
          player.set_shortcut_toggled = function() end
          player.request_translation = function(localised)
            player.next_translation_id = player.next_translation_id + 1
            player.translation_requests[#player.translation_requests + 1] = {id = player.next_translation_id, localised = localised}
            return player.next_translation_id
          end
          library.open(player)
          assert(#player.translation_requests == 0)
          library.on_translation_maintenance({tick = 1800})
          assert(#player.translation_requests == 1 and library.subscription_needs())
        ''')

    def test_retired_translation_callbacks_resume_an_open_reused_player_without_publishing_old_labels(self):
        self.lua.execute('''
          boot()
          library.open(player, {family = "all"})
          local old_gear, old_foreign = player.translation_requests[1].id, player.translation_requests[2].id
          library.on_player_removed({player_index = 1})
          assert(storage.mir_library.players[1] == nil and library.subscription_needs())

          screen = gui_container(nil)
          player = {
            valid = true, index = 1, locale = "en", connected = true, gui = {screen = screen},
            force = {index = 1, technologies = {[gear.name] = gear, [foreign.name] = foreign},
              research_queue = {}, current_research = nil},
            translation_requests = {}, next_translation_id = 100
          }
          player.set_shortcut_toggled = function() end
          player.request_translation = function(localised)
            player.next_translation_id = player.next_translation_id + 1
            local request = {id = player.next_translation_id, localised = localised}
            player.translation_requests[#player.translation_requests + 1] = request
            return request.id
          end
          library.open(player)
          local root = player.gui.screen["mir_research_browser"]
          assert(#player.translation_requests == 0 and root ~= nil,
            "reused index issued while retired native IDs remained")

          library.on_string_translated({player_index = 1, id = old_gear,
            translated = true, result = "old player gear"})
          assert(#player.translation_requests == 0
            and research_content(root)["mir_library_list_pane"]["mir_library_results"].items[1][3] == "Iron gear wheel productivity")
          library.on_string_translated({player_index = 1, id = old_foreign,
            translated = true, result = "old player foreign"})
          assert(#player.translation_requests == 1 and player.translation_requests[1].id == 101,
            "last retired callback did not resume the already open replacement player")
          assert(research_content(root)["mir_library_list_pane"]["mir_library_results"].items[1][3] == "Iron gear wheel productivity",
            "retired callback published into the replacement player's view")
        ''')

    def test_status_filter_persists_read_only_queue_context_and_cap_explanation(self):
        self.lua.execute('''
          boot()
          library.open(player)
          local root = player.gui.screen["mir_research_browser"]
          local status = research_filters(root)["mir_library_filter_grid"]["mir_library_status_field"]["mir_library_status"]
          status.selected_index = 4
          library.on_gui_selection_state_changed({player_index = 1, element = status})

          root = player.gui.screen["mir_research_browser"]
          local state = storage.mir_library.players[1]
          assert(state.status == 4 and research_filters(root)["mir_library_filter_grid"]["mir_library_status_field"]["mir_library_status"].selected_index == 4)
          local rows = research_content(root)["mir_library_list_pane"]["mir_library_results"]
          assert(#rows.items == 1 and rows.items[1][3] == "Iron gear wheel productivity")
          rows.selected_index = 1
          library.on_gui_selection_state_changed({player_index = 1, element = rows})

          root = player.gui.screen["mir_research_browser"]
          local detail = research_content(root)["mir_library_detail"]
          local context = detail.mir_library_research_facts["mir_library_detail_context"]
          assert(context["mir_library_context_status"].caption[1] == "mir-browser.context-status")
          assert(context["mir_library_context_current"].caption[1] == "mir-browser.context-current")
          assert(context["mir_library_context_queue_count"].caption[1] == "mir-browser.context-queue-count"
            and context["mir_library_context_queue_count"].caption[2] == 1)
          assert(context["mir_library_context_queue_position"].caption[1] == "mir-browser.context-queue-position"
            and context["mir_library_context_queue_position"].caption[2] == 1)
          assert(context["mir_library_context_queue_guidance"]==nil
            and research_content(root).mir_library_list_pane.mir_library_actions.mir_library_open_native.tooltip[1]=="mir-browser.native-queue-guidance")
          assert(detail.mir_library_research_facts["mir_library_detail_cap"].caption[1] == "mir-browser.cap-finite")

          local queue, current, progress = player.force.research_queue, player.force.current_research, player.force.research_progress
          local saved = storage.mir_library
          library.on_load()
          assert(storage.mir_library == saved and storage.mir_library.players[1].status == 4)
          library.close(player)
          library.open(player)
          root = player.gui.screen["mir_research_browser"]
          assert(research_filters(root)["mir_library_filter_grid"]["mir_library_status_field"]["mir_library_status"].selected_index == 4)
          assert(player.force.research_queue == queue and player.force.current_research == current
            and player.force.research_progress == progress)
        ''')

    def test_foreign_same_named_root_and_children_never_create_preferences_or_receive_callbacks(self):
        self.lua.execute('''
          boot()
          local foreign = player.gui.screen.add{type = "frame", name = "mir_research_browser"}
          local filters = foreign.add{type = "flow", name = "mir_library_filters"}
          local query = filters.add{type = "textfield", name = "mir_library_query", text = "foreign text"}
          local family = filters.add{type = "drop-down", name = "mir_library_family", selected_index = 2}
          local status = filters.add{type = "drop-down", name = "mir_library_status", selected_index = 4}
          local content = foreign.add{type = "flow", name = "mir_library_content"}
          local results = content.add{type = "list-box", name = "mir_library_results", selected_index = 1}
          local actions = content.add{type = "flow", name = "mir_library_actions"}
          local close = actions.add{type = "button", name = "mir_library_close"}
          local open_native = actions.add{type = "button", name = "mir_library_open_native"}
          foreign.location = {x = 17, y = 29}

          -- Ordinary entry points see the collision, leave it alone, and do
          -- not allocate a private player preference merely to reject it.
          assert(library.open(player) == nil)
          library.close(player)
          library.on_lua_shortcut({prototype_name = "mir-research-browser", player_index = 1})
          assert(next(storage) == nil and foreign.valid)
          assert(player.gui.screen["mir_research_browser"] == foreign and player.shortcut_toggled == nil)

          -- Every routed GUI callback must prove the tagged root and all of
          -- its ancestors, rather than accepting a globally shared name.
          query.text = "attempted mutation"
          library.on_gui_text_changed({player_index = 1, element = query})
          library.on_gui_selection_state_changed({player_index = 1, element = family})
          library.on_gui_selection_state_changed({player_index = 1, element = status})
          library.on_gui_selection_state_changed({player_index = 1, element = results})
          library.on_gui_click({player_index = 1, element = close})
          library.on_gui_click({player_index = 1, element = open_native})
          library.on_gui_location_changed({player_index = 1, element = foreign})
          library.on_gui_closed({player_index = 1, element = foreign})
          assert(next(storage) == nil and foreign.valid)
          assert(query.text == "attempted mutation" and family.selected_index == 2 and status.selected_index == 4)
          assert(player.gui.screen["mir_research_browser"] == foreign and player.opened_technology == nil)
        ''')

    def test_foreign_or_replaced_same_named_lifecycle_events_preserve_the_live_owned_window(self):
        self.lua.execute('''
          boot()
          local retired = library.open(player)
          library.close(player)
          local root = library.open(player, {query="gear", selected=gear.name})
          assert(retired ~= root and not retired.valid)
          root.location = {x=31, y=41}
          library.on_gui_location_changed({player_index=1, element=root})
          local function live_view() return storage.mir_library.players[1] end
          local peer = {query="peer search", location={x=61, y=71}}
          storage.mir_library.players[2] = peer
          local queue, current, progress = player.force.research_queue,
            player.force.current_research, player.force.research_progress
          local level, enabled = gear.level, gear.enabled
          local container = screen.add{type="flow", name="foreign_container"}
          local foreign_root = container.add{type="frame", name="mir_research_browser"}
          foreign_root.location = {x=901, y=902}
          local named_child = root.add{type="frame", name="mir_research_browser"}
          named_child.location = {x=701, y=702}

          for _, element in ipairs{foreign_root, named_child, retired} do
            library.on_gui_location_changed({player_index=1, element=element})
            assert(live_view().location.x == 31 and live_view().location.y == 41,
              "same-named foreign or stale roots must not replace the owned location")
            library.on_gui_closed({player_index=1, element=element})
            assert(root.valid and player.gui.screen["mir_research_browser"] == root
              and player.opened == root and player.shortcut_toggled == true,
              "same-named foreign or stale roots must not close the owned Library")
          end
          library.on_gui_closed({player_index=99, element=root})
          library.on_gui_closed({player_index=1})
          library.on_gui_closed(nil)
          assert(root.valid and live_view().query == "gear" and live_view().selected == gear.name)
          assert(storage.mir_library.players[2] == peer
            and peer.query == "peer search" and peer.location.x == 61)

          root.location = {x=83, y=94}
          library.on_gui_location_changed({player_index=1, element=root})
          assert(live_view().location.x == 83 and live_view().location.y == 94,
            "the actual owned root must still persist its position")
          library.on_gui_closed({player_index=1, element=root})
          assert(not root.valid and player.gui.screen["mir_research_browser"] == nil
            and player.shortcut_toggled == false and live_view().location.x == 83)
          assert(foreign_root.valid and storage.mir_library.players[2] == peer)
          assert(queue == player.force.research_queue and current == player.force.current_research
            and progress == player.force.research_progress and level == gear.level and enabled == gear.enabled,
            "GUI lifecycle events must preserve native research and the peer's personal view")
        ''')

    def test_real_model_readiness_uses_completed_disabled_and_trigger_explanations(self):
        self.lua.execute('''
          package.preload["presentation.library_model"] = nil
          package.loaded["presentation.library_model"] = nil
          boot()
          gear.prototype.hidden = false
          player.force.research_queue, player.force.current_research = {}, nil
          local function status()
            local root = library.open(player, {selected=gear.name})
            local context = research_content(root)["mir_library_detail"].mir_library_research_facts["mir_library_detail_context"]
            return context["mir_library_context_status"].caption[2][1]
          end
          assert(status() == "mir-browser.status-complete",
            "completed research must have its native completion explanation")
          gear.researched = false
          assert(status() == "mir-browser.status-disabled",
            "disabled research must have its native disablement explanation")
          gear.enabled = true
          gear.prototype.research_trigger = {type="craft-item", item="iron-plate", count=1}
          assert(status() == "mir-browser.status-locked",
            "the modern Library host must supply its trigger capability to the pure model")
        ''')

    def test_cap_provider_is_configured_without_force_extension_or_periodic_work(self):
        self.lua.execute('''
          package.preload["research.catalogue"] = nil
          package.preload["presentation.library_model"] = nil
          package.loaded["research.catalogue"] = nil
          package.loaded["presentation.library_model"] = nil
          boot()
          cap_calls = 0
          library.set_cap_provider(function(actual_force)
            assert(actual_force == player.force)
            cap_calls = cap_calls + 1
            return {[gear.name] = 2}
          end)
          library.on_load()
          assert(cap_calls == 0 and library.subscription_needs() == false)
          library.open(player)
          local root = player.gui.screen["mir_research_browser"]
          local detail = research_content(root)["mir_library_detail"]
          assert(cap_calls == 1 and detail.mir_library_research_facts["mir_library_detail_cap"] ~= nil)
          local rows = research_content(root)["mir_library_list_pane"]["mir_library_results"]
          rows.selected_index = 1
          library.on_gui_selection_state_changed({player_index = 1, element = rows})
          root = player.gui.screen["mir_research_browser"]
          detail = research_content(root)["mir_library_detail"]
          assert(cap_calls == 2)
          assert(detail.mir_library_research_facts["mir_library_detail_level"].caption[1] == "mir-browser.level-cap")
          assert(detail.mir_library_research_facts["mir_library_detail_cap"].caption[1] == "mir-browser.cap-finite"
            and detail.mir_library_research_facts["mir_library_detail_cap"].caption[2] == 2
            and detail.mir_library_research_facts["mir_library_detail_cap"].caption[3] == "ips-max-level-research_gears")
          local ok = pcall(function() library.set_cap_provider("not a function") end)
          assert(not ok)
        ''')

    def test_native_navigation_rejects_missing_selection_before_native_technology_lookup(self):
        self.lua.execute('''
          boot()
          library.open(player)
          local original_force = player.force
          player.force = setmetatable({}, {__index = function(_, key)
            error("missing selection read native force field: " .. tostring(key))
          end})
          library.on_gui_click({player_index = 1,
            element = {valid = true, name = "mir_library_open_native"}})
          assert(player.opened_technology == nil)
          player.force = original_force
        ''')

    def test_real_catalogue_and_model_handoff_filters_the_native_gear_row(self):
        self.lua.execute('''
          package.preload["research.catalogue"] = nil
          package.preload["presentation.library_model"] = nil
          package.loaded["research.catalogue"] = nil
          package.loaded["presentation.library_model"] = nil
          script = {active_mods={base="2.1.23"}}
          boot()
          -- Native callbacks cannot import modules, including cached ones.
          require = function(name) error("Library callback imported " .. name) end
          library.on_lua_shortcut({prototype_name = "mir-research-browser", player_index = 1})
          local root = player.gui.screen["mir_research_browser"]
          local query = research_filters(root)["mir_library_query"]
          query.text = "research_gears"
          library.on_gui_text_changed({player_index = 1, element = query})
          root = player.gui.screen["mir_research_browser"]
          local results = research_content(root)["mir_library_list_pane"]["mir_library_results"]
          assert(#results.items == 1 and results.items[1][3] == gear.localised_name)
          results.selected_index = 1
          library.on_gui_selection_state_changed({player_index = 1, element = results})
          assert(storage.mir_library.players[1].selected == gear.name)
          assert(research_content(player.gui.screen["mir_research_browser"])["mir_library_detail"] ~= nil)
        ''')

    def _assert_real_selected_catalogue_opens_without_runtime_imports(self, profile_name, target_id, expected_id):
        editions = json.loads((ROOT / "targets/editions.json").read_text(encoding="utf-8"))["targets"]
        profile = json.loads((ROOT / f"tests/profiles/{profile_name}.json").read_text(encoding="utf-8"))
        target = self.lua.table_from(editions[target_id])
        target["id"] = target_id
        self.lua.globals().selected_target = target
        self.lua.globals().selected_mods = self.lua.table_from({
            mod["name"]: mod["version"] for mod in profile["mods"] if mod["enabled"]
        })
        self.lua.globals().expected_id = expected_id
        self.lua.execute(r'''
          package.loaded["platform.target"] = selected_target
          script, mods = {active_mods=selected_mods}, selected_mods
          package.preload["research.catalogue"] = nil
          package.preload["presentation.library_model"] = nil
          package.loaded["research.catalogue"] = nil
          package.loaded["presentation.library_model"] = nil
          package.loaded["runtime.library"] = nil

          -- control.lua parsing: real selected adapters and their
          -- declarations load before Factorio begins callbacks.
          boot()
          local catalogue = package.loaded["research.catalogue"]
          local modern = package.loaded["compatibility.modern_catalogue"]
          assert(type(catalogue) == "table" and type(modern) == "table")
          local before = catalogue.declared()
          local found = false
          for _, row in ipairs(before) do
            if row.id == expected_id then found = true end
          end
          assert(found, "selected closure omitted " .. expected_id)

          local select, selections = modern.select, 0
          modern.select = function(...)
            selections = selections + 1
            return select(...)
          end
          -- Factorio rejects every require after parsing, including a
          -- cached module.  Library.open must consume its parsed rows.
          require = function(name) error("post-parse require: " .. tostring(name)) end

          before[1].id = "foreign"
          local after = catalogue.declared()
          assert(after[1].id == "recipe-prod-research_gears-1",
            "Library catalogue returned caller-owned rows")
          local root = library.open(player, {selected=gear.name})
          assert(root == player.gui.screen["mir_research_browser"]
            and storage.mir_library.players[1].selected == gear.name)
          assert(selections == 0, "Library rebuilt selected adapters after parsing")
        ''')

    def test_real_space_age_catalogue_opens_without_runtime_imports(self):
        self._assert_real_selected_catalogue_opens_without_runtime_imports(
            "space-age-f210-2123", "f210", "recipe-prod-research_agricultural_growth_speed-1")

    def test_real_py_catalogue_opens_without_runtime_imports(self):
        self._assert_real_selected_catalogue_opens_without_runtime_imports(
            "py-coal-f200-2077", "f200", "recipe-prod-research_material_py_log-1")

    def test_real_bob_core_catalogue_opens_without_runtime_imports(self):
        self._assert_real_selected_catalogue_opens_without_runtime_imports(
            "bob-core-f210-2123", "f210", "recipe-prod-research_material_tin-1")

    def test_level_modes_filter_real_native_rows_and_preserve_owned_personal_state(self):
        self.lua.execute('''
          package.preload["research.catalogue"], package.preload["presentation.library_model"] = nil, nil
          package.loaded["research.catalogue"], package.loaded["presentation.library_model"] = nil, nil
          boot()
          local native_queue, native_current = player.force.research_queue, player.force.current_research
          library.open(player, {family = "all", mode = 2, page = 7})
          local view = storage.mir_library.players[1]
          local root = player.gui.screen["mir_research_browser"]
          local filters, content = research_filters(root), research_content(root)
          local query, mode = filters["mir_library_query"], filters["mir_library_filter_grid"]["mir_library_mode_field"]["mir_library_mode"]
          assert(view.mode == 2 and view.page == 7 and mode.selected_index == 2)
          assert(#content["mir_library_list_pane"]["mir_library_results"].items == 1
            and content["mir_library_list_pane"]["mir_library_results"].items[1][3] == foreign.localised_name)

          mode.selected_index = 3
          library.on_gui_selection_state_changed({player_index = 1, element = mode})
          view = storage.mir_library.players[1]
          assert(view.mode == 3 and view.page == 1 and view.scroll == 1)
          assert(filters["mir_library_query"] == query and filters["mir_library_filter_grid"]["mir_library_mode_field"]["mir_library_mode"] == mode)
          assert(#content["mir_library_list_pane"]["mir_library_results"].items == 1
            and content["mir_library_list_pane"]["mir_library_results"].items[1][3] == gear.localised_name)

          library.open(player, {page = 7})
          for _, invalid in ipairs({0, 4, 1.5, "2", 0/0}) do
            library.open(player, {mode = invalid})
            view = storage.mir_library.players[1]
            assert(view.mode == 3 and view.page == 7, "invalid mode reset accepted state")
          end
          local foreign_root = player.gui.screen.add{type = "frame", name = "foreign-frame"}
          local foreign_filters = foreign_root.add{type = "flow", name = "mir_library_filters"}
          local spoof = foreign_filters.add{type = "drop-down", name = "mir_library_mode", selected_index = 1}
          library.on_gui_selection_state_changed({player_index = 1, element = spoof})
          view = storage.mir_library.players[1]
          assert(view.mode == 3 and view.page == 7, "foreign GUI changed the personal mode")
          mode.selected_index = 4
          library.on_gui_selection_state_changed({player_index = 1, element = mode})
          view = storage.mir_library.players[1]
          assert(view.mode == 3 and view.page == 7)

          library.close(player); library.on_load(); library.open(player)
          root = player.gui.screen["mir_research_browser"]
          assert(research_filters(root)["mir_library_filter_grid"]["mir_library_mode_field"]["mir_library_mode"].selected_index == 3
            and storage.mir_library.players[1].mode == 3)
          -- Published modes classify an effective capped infinity as finite.
          library.set_cap_provider(function() return {[gear.name] = 2} end)
          library.open(player, {mode = 2})
          assert(#research_content(root)["mir_library_list_pane"]["mir_library_results"].items == 2)
          assert(player.force.research_queue == native_queue and player.force.current_research == native_current
            and player.force.research_progress == .5 and gear.level == 3 and gear.enabled == false)
        ''')

    def test_historical_filter_order_hidden_page_and_selection_options_drive_real_library_state(self):
        self.lua.execute('''
          package.preload["research.catalogue"] = nil
          package.preload["presentation.library_model"] = nil
          package.loaded["research.catalogue"] = nil
          package.loaded["presentation.library_model"] = nil
          boot()

          library.open(player, {family = "all", status = 1, sort = "name-desc", page = 7,
            selected = gear.name})
          local view = storage.mir_library.players[1]
          local root = player.gui.screen["mir_research_browser"]
          assert(view.family == "all" and view.status == 1 and view.sort == "name-desc"
            and view.stable_sort == "progression" and view.page == 7
            and next(view.hidden) == nil and view.selected == gear.name)
          assert(research_filters(root)["mir_library_filter_grid"]["mir_library_sort_field"]["mir_library_sort"].selected_index == 4)
          local rows = research_content(root)["mir_library_list_pane"]["mir_library_results"]
          assert(#rows.items == 2 and rows.items[1][3] == gear.localised_name and rows.items[2][3] == foreign.localised_name)

          -- The historical page value survives reopening, but it was never a
          -- player-list paginator: the continuous list retains both rows.
          library.close(player)
          library.open(player)
          view = storage.mir_library.players[1]
          root = player.gui.screen["mir_research_browser"]
          rows = research_content(root)["mir_library_list_pane"]["mir_library_results"]
          assert(view.page == 7 and #rows.items == 2
            and rows.items[1][3] == gear.localised_name and rows.items[2][3] == foreign.localised_name)

          -- The valid dense remote list changes actual rendering and an
          -- explicit valid page wins over the normal filter page reset.
          library.open(player, {hidden = {foreign.name}, page = 7})
          view = storage.mir_library.players[1]
          root = player.gui.screen["mir_research_browser"]
          rows = research_content(root)["mir_library_list_pane"]["mir_library_results"]
          assert(view.hidden[foreign.name] and view.page == 7
            and #rows.items == 1 and rows.items[1][3] == gear.localised_name)

          -- Invalid remote-style values leave each previously accepted field
          -- untouched, including unknown selected and hidden technologies.
          library.open(player, {status = 5, sort = "invalid", page = 30001,
            selected = "unknown", hidden = {gear.name, "unknown"}})
          view = storage.mir_library.players[1]
          assert(view.status == 1 and view.sort == "name-desc" and view.page == 7
            and view.selected == gear.name and view.hidden[foreign.name]
            and not view.hidden[gear.name])

          -- A real filter operation resets the persisted historical page; the
          -- continuous current list deliberately does not pretend to paginate.
          local query = research_filters(root)["mir_library_query"]
          query.text = "research_gears"
          library.on_gui_text_changed({player_index = 1, element = query})
          view = storage.mir_library.players[1]
          assert(view.page == 1 and view.query == "research_gears")

          root = player.gui.screen["mir_research_browser"]
          local sort = research_filters(root)["mir_library_filter_grid"]["mir_library_sort_field"]["mir_library_sort"]
          sort.selected_index = 2
          library.on_gui_selection_state_changed({player_index = 1, element = sort})
          view = storage.mir_library.players[1]
          assert(view.sort == "native" and view.stable_sort == "native" and view.page == 1)

          local status = research_filters(root)["mir_library_filter_grid"]["mir_library_status_field"]["mir_library_status"]
          status.selected_index = 4
          library.on_gui_selection_state_changed({player_index = 1, element = status})
          view = storage.mir_library.players[1]
          assert(view.status == 4 and view.page == 1)
        ''')

    def test_real_model_host_preserves_hidden_visibility_and_full_family_callbacks(self):
        self.lua.execute('''
          package.preload["research.catalogue"] = function()
            return {internal_credit_ids = function() return {} end, declared = function()
              return {
                {id = "recipe-prod-research_gears-1", family = "research_gears", progression = 1,
                  native_order = "p[research_gears]"},
                {id = "agricultural-growth-speed", family = "research_agricultural_growth_speed", progression = 2,
                  native_order = "p[agricultural-growth-speed]"},
                {id = "spoilage-preservation", family = "research_spoilage_preservation", progression = 3,
                  native_order = "p[spoilage-preservation]"}
              }
            end}
          end
          package.preload["presentation.library_model"] = nil
          package.loaded["research.catalogue"], package.loaded["presentation.library_model"] = nil, nil
          boot()
          local native_queue, native_current = player.force.research_queue, player.force.current_research

          gear.localised_name = {"technology-name.more-infinite-research.research_gears", "Iron gear wheel"}
          -- The actual model receives authored descriptor metadata. Its gear
          -- selector is declaration-only: the foreign force row must not
          -- leak into it or cause a native catalogue traversal.
          library.open(player, {family = "research_gears", page = 7})
          local view = storage.mir_library.players[1]
          local root = player.gui.screen["mir_research_browser"]
          local filters, content = research_filters(root), research_content(root)
          local family, visibility = filters["mir_library_filter_grid"]["mir_library_family_field"]["mir_library_family"], filters["mir_library_filter_grid"]["mir_library_visibility_field"]["mir_library_visibility"]
          assert(view.family == "research_gears" and view.visibility == 1 and view.page == 7)
          assert(family.selected_index == 5 and visibility.selected_index == 1)
          assert(family.items[5] == gear.localised_name,
            "authored family caption dropped the complete native localization parameters")
          assert(#player.translation_requests == 1)
          assert(#content["mir_library_list_pane"]["mir_library_results"].items == 1
            and content["mir_library_list_pane"]["mir_library_results"].items[1][3] == gear.localised_name)

          library.close(player); library.on_load(); library.open(player)
          root = player.gui.screen["mir_research_browser"]
          filters, content = research_filters(root), research_content(root)
          family, visibility = filters["mir_library_filter_grid"]["mir_library_family_field"]["mir_library_family"], filters["mir_library_filter_grid"]["mir_library_visibility_field"]["mir_library_visibility"]
          assert(storage.mir_library.players[1].family == "research_gears"
            and filters["mir_library_filter_grid"]["mir_library_family_field"]["mir_library_family"].selected_index == 5
            and #content["mir_library_list_pane"]["mir_library_results"].items == 1
            and content["mir_library_list_pane"]["mir_library_results"].items[1][3] == gear.localised_name)

          -- External is the published native scope. It is the only selector
          -- here that includes the actual foreign technology.
          family = filters["mir_library_filter_grid"]["mir_library_family_field"]["mir_library_family"]
          family.selected_index = 3
          library.on_gui_selection_state_changed({player_index = 1, element = family})
          view = storage.mir_library.players[1]
          assert(view.family == "external" and view.page == 1
            and #content["mir_library_list_pane"]["mir_library_results"].items == 1
            and content["mir_library_list_pane"]["mir_library_results"].items[1][3] == foreign.localised_name)

          -- Remote-style input stays strict and cannot replace a persisted
          -- hidden-only selection or its explicitly retained page.
          library.open(player, {hidden = {foreign.name}, visibility = 2, page = 7})
          for _, invalid in ipairs({0, 4, 1.5, "2", 0/0}) do
            library.open(player, {visibility = invalid})
            view = storage.mir_library.players[1]
            assert(view.visibility == 2 and view.page == 7)
          end
          library.open(player, {family = "unknown-family"})
          view = storage.mir_library.players[1]
          assert(view.family == "external" and view.visibility == 2 and view.page == 7)
          local foreign_root = player.gui.screen.add{type = "frame", name = "foreign-visibility-frame"}
          local foreign_filters = foreign_root.add{type = "flow", name = "mir_library_filters"}
          local spoof = foreign_filters.add{type = "drop-down", name = "mir_library_visibility", selected_index = 1}
          library.on_gui_selection_state_changed({player_index = 1, element = spoof})
          view = storage.mir_library.players[1]
          assert(view.visibility == 2 and view.page == 7, "foreign GUI changed hidden visibility")
          visibility.selected_index = 3
          library.on_gui_selection_state_changed({player_index = 1, element = visibility})
          view = storage.mir_library.players[1]
          assert(view.visibility == 3 and view.page == 1)
          assert(research_content(root)["mir_library_availability_empty"] == nil)
          assert(research_content(root)["mir_library_availability_1"].caption[2][1]
              == "technology-name.more-infinite-research.research_agricultural_growth_speed"
            and research_content(root)["mir_library_availability_2"].caption[2][1]
              == "technology-name.more-infinite-research.research_spoilage_preservation")
          family.selected_index = 7
          library.on_gui_selection_state_changed({player_index = 1, element = family})
          view = storage.mir_library.players[1]
          assert(view.family == "external" and view.page == 1, "invalid owned family was accepted")

          visibility.selected_index = 1
          library.on_gui_selection_state_changed({player_index = 1, element = visibility})
          view = storage.mir_library.players[1]
          assert(view.visibility == 1 and view.page == 1 and view.scroll == 1)
          assert(#content["mir_library_list_pane"]["mir_library_results"].items == 0)
          assert(player.force.research_queue == native_queue and player.force.current_research == native_current
            and player.force.research_progress == .5 and gear.level == 3 and gear.enabled == false)
        ''')

    def test_configuration_migrates_published_browser_view_without_dropping_later_fidelity_fields(self):
        self.lua.execute(r'''
          package.preload["research.catalogue"], package.preload["presentation.library_model"] = nil, nil
          package.loaded["research.catalogue"], package.loaded["presentation.library_model"] = nil, nil
          boot()
          -- Independent captured schema-3 shape from the published 4.7 browser.
          -- These values are deliberately not derived from MIR5 migration code.
          local historical = {
            schema = 3, mode = 3, status = 2, page = 7, search = "historical gear",
            tab = "settings", setting_selection = "ips-cost-base-research_gears",
            settings_scope = "options", effect_page = 4, family = "all",
            sort = "name-asc", stable_sort = "native", settings_search = "cost tuning",
            visibility = 2, selected = gear.name, location = {x = 12, y = 19},
            scroll = 6, hidden = {["foreign-research"] = true},
            geometry = {width = 900, height = 700},
            report_settings = false, report_omissions = true,
            report_destination = "script-output/browser-1-42.txt"
          }
          local published_availability = {schema = 3, tab = "research", visibility = 3,
            family = "mir", mode = 1, status = 1, page = 1, sort = "progression"}
          storage.mir = {research_browser = {players = {
            [1] = historical, [2] = published_availability
          }}}
          local old = player.gui.screen.add{type = "frame", name = "mir_research_browser"}
          old.location = {x = 55, y = 66}
          old.add{type = "tabbed-pane", name = "mir_browser_tabs"}

          library.on_configuration_changed()

          local state = storage.mir_library
          local view = state.players[1]
          assert(view.query == "historical gear" and view.family == "all" and view.status == 2 and view.mode == 3)
          assert(view.selected == gear.name and view.scroll == 6 and view.page == 7 and view.visibility == 2)
          assert(view.sort == "name-asc" and view.stable_sort == "native"
            and view.hidden["foreign-research"])
          assert(view.tab == "settings" and view.settings_scope == "options"
            and view.settings_query == "cost tuning" and view.setting_selected == "ips-cost-base-research_gears")
          assert(view.geometry.width == 900 and view.geometry.height == 700)
          assert(state.players[2].tab == "research" and state.players[2].visibility == 3)
          -- The current frame location is the starting point, then the
          -- oversized saved frame is clamped fully onto the display.
          assert(view.location.x == 55 and view.location.y == 24)
          assert(storage.mir.research_browser.players[1] == historical)
          local preserved = state.legacy_browser
          assert(preserved.version == 1 and preserved.source == "storage.mir.research_browser")
          assert(preserved.authoritative_source == "storage.mir.research_browser")
          assert(preserved.snapshot_status[1].complete and not preserved.snapshot_status[1].truncated)
          assert(preserved.players[2].visibility == 3)
          local saved = preserved.players[1]
          assert(saved.mode == 3 and saved.status == 2 and saved.page == 7)
          assert(saved.tab == "settings" and saved.settings_scope == "options")
          assert(saved.sort == "name-asc" and saved.stable_sort == "native")
          assert(saved.settings_search == "cost tuning" and saved.visibility == 2)
          assert(saved.hidden["foreign-research"] and saved.geometry.width == 900)
          assert(saved.report_settings == false and saved.report_omissions == true)
          assert(old.valid == false)
          local root = player.gui.screen["mir_research_browser"]
          assert(root and root ~= old and research_filters(root) and root["mir_library_tabs"] and research_content(root))
          assert(player.shortcut_toggled == true)
        ''')

    def test_delivered_tabs_show_effective_startup_settings_and_keep_native_queue_authoritative(self):
        self.lua.execute(r'''
          boot()
          helpers = {
            encode_string = function(text) return text end,
            decode_string = function(text) return text end,
            json_to_table = function(text)
              if text == "library-profile" then return {
                schema = 1, kind = "mir-settings-profile", settings = {
                  ["ips-cost-base-research_gears"] = 777
                }
              } end
            end
          }
          settings = {startup = {
            ["ips-enable-research_gears"] = {value = false},
            ["ips-cost-base-research_gears"] = {value = 4242},
            ["mir-settings-profile-import"] = {value = "MIRSET1:library-profile"}
          }}
          library.open(player, {tab = "settings", settings_scope = "research", settings_search = "research_gears"})
          local root = player.gui.screen["mir_research_browser"]
          local tabs = root["mir_library_tabs"]
          assert(tabs.type == "tabbed-pane" and #tabs._tabs == 4 and tabs.selected_tab_index == 3)
          local settings_content = tabs["mir_library_settings_content"]
          local settings_dynamic = settings_content["mir_library_settings_dynamic"]
          assert(storage.mir_library.players[1].tab == "settings"
            and settings_dynamic["mir_library_settings_count"].caption[1] == "mir-browser.settings-count")
          local enabled = settings_dynamic["mir_library_settings_detail"].mir_library_settings_fields["mir_library_setting_1_value"]
          assert(enabled.caption[1] == "mir-browser.setting-with-default" and enabled.caption[2][1] == "mir-browser.setting-off"
            and enabled.tooltip[2][1] == "mir-browser.setting-off"
            and enabled.tooltip[3][1] == "mir-browser.setting-on"
            and enabled.tooltip[4][1] == "mir-browser.source-direct")
          local enabled_source = settings_dynamic["mir_library_settings_detail"].mir_library_settings_fields["mir_library_setting_1_source"]
          assert(enabled_source==nil and enabled.tooltip[4][1]=="mir-browser.source-direct")
          local cost = settings_dynamic["mir_library_settings_detail"].mir_library_settings_fields["mir_library_setting_2_value"]
          assert(cost.caption[1]=="mir-browser.setting-with-default" and cost.caption[2] == "777" and cost.tooltip[1] == "mir-browser.setting-provenance"
            and cost.tooltip[2] == "4242" and cost.tooltip[4][1] == "mir-browser.source-mirset1")
          local settings_query = settings_content["mir_library_settings_query"]
          settings_query.text = "gears"
          library.on_gui_text_changed({player_index = 1, element = settings_query})
          assert(settings_content["mir_library_settings_query"] == settings_query
            and settings_query.valid and settings_query.text == "gears")
          local settings_list = settings_dynamic["mir_library_settings_list"]
          settings_list.selected_index = 1
          library.on_gui_selection_state_changed({player_index = 1, element = settings_list})
          assert(storage.mir_library.players[1].setting_selected == "research_gears"
            and settings_content["mir_library_settings_query"] == settings_query)
          assert(#player.translation_requests > 0,
            "settings view should request translated setting labels for localized search")

          tabs.selected_tab_index = 2
          library.on_gui_selected_tab_changed({player_index = 1, element = tabs})
          local queue = tabs["mir_library_queue_content"]
          assert(storage.mir_library.players[1].tab == "queue"
            and #queue["mir_library_queue_list"].items == 1)
          local original_queue, original_current, original_progress = player.force.research_queue,
            player.force.current_research, player.force.research_progress
          queue["mir_library_queue_list"].selected_index = 1
          library.on_gui_selection_state_changed({player_index = 1, element = queue["mir_library_queue_list"]})
          assert(storage.mir_library.players[1].tab == "research"
            and storage.mir_library.players[1].selected == gear.name)
          assert(player.force.research_queue == original_queue and player.force.current_research == original_current
            and player.force.research_progress == original_progress)

          -- Published callers could still request Availability. It routed to
          -- Research's third visibility choice rather than a fifth tab.
          library.open(player, {tab = "availability"})
          assert(storage.mir_library.players[1].tab == "research"
            and storage.mir_library.players[1].visibility == 3)
          assert(research_content(root)["mir_library_availability_empty"] == nil)
          assert(research_content(root)["mir_library_availability_1"] ~= nil
            and research_content(root)["mir_library_availability_2"] ~= nil)
          tabs.selected_tab_index = 4
          library.on_gui_selected_tab_changed({player_index = 1, element = tabs})
          assert(debug_tools(tabs["mir_library_help_content"])["mir_library_help_versions"].caption[1]
            == "mir-browser.debug-versions")
        ''')

    def test_localized_settings_search_survives_load_without_rebuilding_its_request_scope(self):
        self.lua.execute(r'''
          boot()
          local catalog = require("research.settings")
          local names, specs, setting_prototype = catalog.registered_names(), {}, nil
          for _, prototype in ipairs(catalog.prototypes()) do specs[prototype.name] = prototype end
          local target = names[1]
          assert(type(target) == "string" and specs[target] and specs[target].localised_name)
          local scope = catalog.spec(target).stream and "research" or "options"
          library.open(player, {tab="settings", settings_scope=scope})
          assert(#player.translation_requests > 0)
          local target_request
          for _, request in ipairs(player.translation_requests) do
            local function equal(left, right)
              if type(left) ~= type(right) then return false end
              if type(left) ~= "table" then return left == right end
              for key, value in pairs(left) do if not equal(value, right[key]) then return false end end
              for key in pairs(right) do if left[key] == nil then return false end end
              return true
            end
            if equal(request.localised, specs[target].localised_name) then target_request = request; break end
          end
          assert(target_request, "the settings translation batch omitted its first declared label")

          package.loaded["runtime.library"] = nil
          library = require("runtime.library")
          library.on_load()
          library.on_string_translated({player_index=1, id=target_request.id,
            translated=true, result="localized-setting-needle"})

          local root = player.gui.screen["mir_research_browser"]
          local content = root["mir_library_tabs"]["mir_library_settings_content"]
          local query = content["mir_library_settings_query"]
          query.text = "localized-setting-needle"
          library.on_gui_text_changed({player_index=1, element=query})
          local dynamic = content["mir_library_settings_dynamic"]
          local list = dynamic["mir_library_settings_list"]
          assert(#list.items == 1 and dynamic["mir_library_settings_count"].caption[2] == 1,
            "the localized field label should find its group after loading")
        ''')

    def test_new_tab_and_settings_callbacks_do_not_claim_an_unowned_gui(self):
        self.lua.execute(r'''
          boot()
          local foreign = player.gui.screen.add{type = "frame", name = "mir_research_browser"}
          local tabs = foreign.add{type = "tabbed-pane", name = "mir_library_tabs"}
          tabs.selected_tab_index = 2
          local settings_content = tabs.add{type = "flow", name = "mir_library_settings_content"}
          local settings_query = settings_content.add{type = "textfield", name = "mir_library_settings_query", text = "foreign"}
          local settings_list = settings_content.add{type = "list-box", name = "mir_library_settings_list", selected_index = 1}
          local toolbar = settings_content.add{type = "flow", name = "mir_library_settings_toolbar"}
          local options = toolbar.add{type = "button", name = "mir_library_settings_options"}
          local queue_content = tabs.add{type = "flow", name = "mir_library_queue_content"}
          local queue_list = queue_content.add{type = "list-box", name = "mir_library_queue_list", selected_index = 1}

          library.on_gui_selected_tab_changed({player_index = 1, element = tabs})
          library.on_gui_text_changed({player_index = 1, element = settings_query})
          library.on_gui_selection_state_changed({player_index = 1, element = settings_list})
          library.on_gui_selection_state_changed({player_index = 1, element = queue_list})
          library.on_gui_click({player_index = 1, element = options})
          assert(next(storage) == nil and foreign.valid and settings_query.text == "foreign")
        ''')

    def test_configuration_marks_a_bounded_legacy_snapshot_without_mutating_its_authoritative_bucket(self):
        self.lua.execute(r'''
          boot()
          local historical = {schema = 3, search = "old", family = "all"}
          for index = 1, 600 do historical["retained-" .. index] = index end
          storage.mir = {research_browser = {players = {[1] = historical}}}

          library.on_configuration_changed()

          local preserved = storage.mir_library.legacy_browser
          local status = preserved.snapshot_status[1]
          assert(preserved.authoritative_source == "storage.mir.research_browser")
          assert(not status.complete and status.truncated and status.entry_limited)
          -- The exact historical record remains the full-fidelity authority.
          assert(storage.mir.research_browser.players[1] == historical)
          assert(historical["retained-600"] == 600)
        ''')

    def test_configuration_preserves_newer_private_view_and_does_not_claim_same_named_foreign_root(self):
        self.lua.execute(r'''
          boot()
          storage.mir_library = {
            schema = 1,
            players = {[1] = {
              schema = 1, query = "newer private query", family = "mir",
              selected = nil, location = {x = 7, y = 8}, scroll = 3
            }}
          }
          local historical = {
            schema = 3, mode = 1, status = 1, page = 1, search = "old query",
            tab = "research", family = "external", sort = "progression",
            stable_sort = "progression", settings_search = "", visibility = 1,
            selected = gear.name, location = {x = 10, y = 20}, scroll = 9
          }
          storage.mir = {research_browser = {players = {[1] = historical}}}
          local foreign = player.gui.screen.add{type = "frame", name = "mir_research_browser"}
          foreign.add{type = "flow", name = "unrelated_same_named_child"}

          library.on_configuration_changed()

          local view = storage.mir_library.players[1]
          assert(view.query == "newer private query" and view.family == "mir" and view.status == 1)
          assert(view.location.x == 7 and view.location.y == 8 and view.scroll == 3)
          assert(storage.mir_library.legacy_browser.players[1].family == "external")
          assert(foreign.valid and player.gui.screen["mir_research_browser"] == foreign)
          assert(player.shortcut_toggled == nil)
        ''')

    def test_source_keeps_event_registration_and_old_compiler_outside_the_slice(self):
        source = (ROOT / "source/runtime/library.lua").read_text()
        self.assertNotIn("script.on_event", source)
        self.assertNotIn("script.on_nth_tick", source)
        self.assertNotIn("remote.add_interface", source)
        self.assertNotIn("prototypes.mir", source)
        self.assertNotIn("force.caps", source)
        self.assertNotIn("game.create_player", source)
        self.assertNotIn("force.research_queue =", source)
        self.assertNotIn("force.add_research", source)
        self.assertNotIn("force.cancel_current_research", source)
        bootstrap = (ROOT / "source/runtime/bootstrap.lua").read_text()
        self.assertIn("on_library_tab_changed", bootstrap)
        self.assertIn("on_gui_selected_tab_changed", bootstrap)


    def test_help_report_choices_are_owned_personal_retained_and_do_not_export_on_refresh(self):
        self.lua.execute(r'''
          local encodes,writes=0,{}
          script={active_mods={base="2.1.23",["more-infinite-research"]="5.0.21001"}}
          helpers={game_version="2.1.23",encode_string=function(text) encodes=encodes+1; return text end,
            decode_string=function(text) return text end,json_to_table=function() return nil end,
            write_file=function(path,data,append,index) writes[#writes+1]={path=path,data=data,index=index} end}
          boot()
          player.print=function() end
          local root=library.open(player,{tab="help"})
          local help=root.mir_library_tabs.mir_library_help_content
          local settings_box,omissions_box=debug_tools(help).mir_library_report_settings,debug_tools(help).mir_library_report_omissions
          assert(settings_box and settings_box.type=="checkbox" and settings_box.state==false)
          assert(omissions_box and omissions_box.type=="checkbox" and omissions_box.state==false)
          local preview=debug_report(help).mir_library_report_preview
          assert(preview and preview.read_only and preview.word_wrap and #writes==0 and encodes==0)
          settings_box.state=true
          library.on_gui_checked_state_changed({player_index=1,element=settings_box})
          assert(storage.mir_library.players[1].report_settings==true and encodes==1 and #writes==0,
            "report setting="..tostring(storage.mir_library.players[1].report_settings).." encodes="..encodes
              .." writes="..#writes.." preview="..preview.text:sub(1,180))
          omissions_box.state=true
          library.on_gui_checked_state_changed({player_index=1,element=omissions_box})
          assert(storage.mir_library.players[1].report_omissions==true and #writes==0)
          local after_change=encodes
          local text=preview.text
          library.open(player,{tab="help"})
          assert(debug_report(help).mir_library_report_preview==preview and preview.text==text and encodes==after_change)
          player.force.research_progress=.75
          library.on_gui_click({player_index=1,element=debug_tools(help).mir_library_report_refresh})
          assert(preview.text:find("Current research progress: 0.75",1,true))
          assert(#writes==0 and encodes==after_change+1)
          after_change=encodes
          local foreign_root=gui_container(nil).add({name="mir_research_browser",tags={}})
          local foreign_help=foreign_root.add({name="mir_library_tabs"}).add({name="mir_library_help_content"})
          local foreign_box=foreign_help.add({name="mir_library_report_settings",type="checkbox",state=false})
          library.on_gui_checked_state_changed({player_index=1,element=foreign_box})
          library.on_gui_checked_state_changed({player_index=2,element=settings_box})
          assert(storage.mir_library.players[1].report_settings==true and #writes==0 and encodes==after_change)
          preview.focus=function() preview.focused=true end
          preview.select_all=function() preview.selected_all=true end
          library.on_gui_click({player_index=1,element=debug_report(help).mir_library_report_select})
          assert(preview.focused and preview.selected_all and #writes==0)
          library.on_gui_click({player_index=1,element=debug_report(help).mir_library_export_diagnostics})
          assert(#writes==2 and writes[2].data==preview.text and writes[2].index==1)
          assert(debug_report(help).mir_library_export_profile.style.maximal_width
            <=debug_report(help).style.maximal_width,
            "an exported profile must fit inside the restored report pane")
          library.close(player)
          local closed_encodes=encodes
          library.on_gui_checked_state_changed({player_index=1,element=settings_box})
          assert(encodes==closed_encodes and #writes==2)
          package.loaded["runtime.library"]=nil
          library=require("runtime.library")
          library.on_load()
          root=library.open(player,{tab="help"})
          help=root.mir_library_tabs.mir_library_help_content
          assert(debug_tools(help).mir_library_report_settings.state and debug_tools(help).mir_library_report_omissions.state)
        ''')

    def test_report_choices_and_previews_stay_separate_for_players_sharing_a_force(self):
        self.lua.execute(r'''
          helpers={write_file=function() error("preview wrote a file") end,
            encode_string=function() error("unchecked preview encoded settings") end}
          boot()
          local peer={valid=true,index=2,name="Bob",locale="de",connected=true,force=player.force,
            gui={screen=gui_container(nil)},display_resolution=player.display_resolution,display_scale=1}
          game.get_player=function(index) return index==1 and player or index==2 and peer or nil end
          local first=library.open(player,{tab="help"}).mir_library_tabs.mir_library_help_content
          local second=library.open(peer,{tab="help"}).mir_library_tabs.mir_library_help_content
          debug_tools(first).mir_library_report_omissions.state=true
          library.on_gui_checked_state_changed({player_index=1,element=debug_tools(first).mir_library_report_omissions})
          assert(storage.mir_library.players[1].report_omissions==true)
          assert(storage.mir_library.players[2].report_omissions==false)
          assert(debug_report(first).mir_library_report_preview.text:find("authored availability",1,true))
          assert(not debug_report(second).mir_library_report_preview.text:find("authored availability",1,true))
          library.on_gui_checked_state_changed({player_index=2,element=debug_tools(first).mir_library_report_omissions})
          assert(storage.mir_library.players[2].report_omissions==false)
          assert(debug_tools(second).mir_library_report_omissions.state==false)
          library.on_player_removed({player_index=2})
          assert(storage.mir_library.players[2]==nil)
        ''')

    def test_existing_beta_help_pane_gains_report_controls_and_configuration_syncs_its_choices(self):
        self.lua.execute(r'''
          local encodes,writes=0,0
          script={active_mods={base="2.1.23",["more-infinite-research"]="5.0.21001"}}
          helpers={game_version="2.1.23",encode_string=function(text) encodes=encodes+1; return text end,
            decode_string=function(text) return text end,json_to_table=function() return nil end,
            write_file=function() writes=writes+1 end}
          boot()
          local root=library.open(player,{tab="help"})
          local help=root.mir_library_tabs.mir_library_help_content
          -- Exact published501 Help shape: two labels, export button and
          -- privacy guidance. Its root/tab ownership already matches MIR5.
          help.clear()
          help.add({type="label",name="mir_library_help_summary"})
          help.add({type="label",name="mir_library_help_queue"})
          help.add({type="button",name="mir_library_export_diagnostics"})
          help.add({type="label",name="mir_library_export_privacy"})
          library.on_configuration_changed({})
          library.on_native_refresh_tick()
          assert(debug_tools(help).mir_library_report_settings and debug_tools(help).mir_library_report_omissions,
            "existing beta Help did not gain the new controls")
          assert(debug_report(help).mir_library_report_preview and encodes==0 and writes==0)
          storage.mir={research_browser={players={[1]={report_settings=true,report_omissions=true}}}}
          storage.mir_library.players[1].report_settings=nil
          storage.mir_library.players[1].report_omissions=nil
          library.on_configuration_changed({})
          library.on_native_refresh_tick()
          assert(debug_tools(help).mir_library_report_settings.state and debug_tools(help).mir_library_report_omissions.state)
          assert(encodes==1 and writes==0)
          local preview=debug_report(help).mir_library_report_preview
          library.on_native_state_changed({force=player.force})
          library.on_native_refresh_tick()
          assert(encodes==1 and writes==0 and debug_report(help).mir_library_report_preview==preview)
        ''')

    def test_removed_player_report_choices_are_not_resurrected_from_retained_legacy_history(self):
        self.lua.execute(r'''
          boot()
          storage.mir={research_browser={players={[1]={search="old-account-private-query",
            report_settings=true,report_omissions=true}}}}
          library.on_configuration_changed({})
          local preserved=storage.mir_library.legacy_browser.players[1]
          assert(preserved.report_settings==true)
          library.on_player_removed({player_index=1})
          player.name="Different account"
          library.on_configuration_changed({})
          assert(storage.mir_library.players[1]==nil,"removed legacy player was imported again")
          library.open(player)
          assert(storage.mir_library.players[1].report_settings==false)
          assert(storage.mir_library.players[1].report_omissions==false)
          assert(storage.mir_library.players[1].query=="")
          assert(storage.mir_library.legacy_browser.players[1]==preserved)
          assert(preserved.search=="old-account-private-query" and preserved.report_settings==true)
        ''')

    def test_configuration_restores_legacy_report_choices_without_overwriting_current_choices(self):
        self.lua.execute(r'''
          boot()
          storage.mir={research_browser={players={[1]={report_settings=false,report_omissions=true}}}}
          library.on_configuration_changed({})
          local view=storage.mir_library.players[1]
          assert(view.report_settings==false and view.report_omissions==true)
          view.report_settings=true
          view.report_omissions=false
          library.on_configuration_changed({})
          assert(storage.mir_library.players[1].report_settings==true)
          assert(storage.mir_library.players[1].report_omissions==false)
          storage.mir=nil
          view=storage.mir_library.players[1]
          view.report_settings=nil
          view.report_omissions=nil
          library.on_configuration_changed({})
          assert(storage.mir_library.players[1].report_settings==false)
          assert(storage.mir_library.players[1].report_omissions==true)
          local before=storage.mir_library.players[1]
          library.on_load()
          assert(storage.mir_library.players[1]==before and before.report_omissions==true)
        ''')

    def test_support_exports_are_owned_local_and_inactive_on_research_views(self):
        def decode(text):
            try:
                value = json.loads(text)
            except (ValueError, TypeError):
                return None
            return self.lua.table_from(value, recursive=True)

        self.lua.globals().decode_export_json = decode
        self.lua.execute('''
          writes, messages = {}, {}
          helpers={game_version="2.1.23",json_to_table=decode_export_json,
            encode_string=function(text) return text end,decode_string=function(text) return text end,
            write_file=function(path,data,append,index)
              writes[#writes+1]={path=path,data=data,append=append,index=index}
            end}
          boot()
          player.name="Alice"
          player.print=function(message) messages[#messages+1]=message end
          script={active_mods={base="2.1.23",["more-infinite-research"]="5.0.21000"}}
          local before_level,before_enabled,before_progress=gear.level,gear.enabled,player.force.research_progress
          local root=library.open(player,{tab="research"})
          library.open(player,{tab="research"})
          assert(#writes==0)
          library.open(player,{tab="settings"})
          local content=root.mir_library_tabs.mir_library_settings_content
          local toolbar=content.mir_library_settings_toolbar
          local full=toolbar.mir_library_export_settings
          assert(full and toolbar.mir_library_export_compact and #writes==0)
          library.on_gui_click({player_index=2,element=full})
          assert(#writes==0)
          library.on_gui_click({player_index=1,element=full})
          assert(#writes==1 and writes[1].index==1 and writes[1].append==false)
          local preview=content.mir_library_export_profile
          assert(preview.read_only and preview.text .. "\\n"==writes[1].data)
          library.on_gui_click({player_index=1,element=toolbar.mir_library_export_compact})
          assert(#writes==2 and not preview.valid)
          assert(content.mir_library_export_profile.text .. "\\n"==writes[2].data)
          local compact_preview=content.mir_library_export_profile
          local writer=helpers.write_file
          helpers.write_file=function() error("disk denied") end
          library.on_gui_click({player_index=1,element=full})
          assert(#writes==2 and not compact_preview.valid and content.mir_library_export_profile==nil)
          assert(messages[#messages]:find("export failed",1,true))
          helpers.write_file=writer
          local foreign_screen=gui_container(nil)
          local foreign_root=foreign_screen.add({name="mir_research_browser",tags={}})
          local tabs=foreign_root.add({name="mir_library_tabs"})
          local settings_tab=tabs.add({name="mir_library_settings_content"})
          local foreign_toolbar=settings_tab.add({name="mir_library_settings_toolbar"})
          library.on_gui_click({player_index=1,element=foreign_toolbar.add({name="mir_library_export_settings"})})
          assert(#writes==2)
          library.open(player,{tab="help"})
          local help=root.mir_library_tabs.mir_library_help_content
          library.on_gui_click({player_index=1,element=debug_report(help).mir_library_export_diagnostics})
          assert(#writes==4 and writes[3].index==1 and writes[4].index==1)
          assert(writes[4].path=="more-infinite-research/mir.log")
          assert(gear.level==before_level and gear.enabled==before_enabled and player.force.research_progress==before_progress)
          library.close(player)
          library.on_gui_click({player_index=1,element=full})
          assert(#writes==4)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LibraryTests))
    sys.exit(0 if result.wasSuccessful() else 1)
