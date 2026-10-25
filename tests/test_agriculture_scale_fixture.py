"""Host controls for the bounded F210 agricultural tower scale witness.

These controls load only fixture-owned Lua against small doubles. They never
launch Factorio or interpret profiler text as a timing result.
"""
import argparse
import json
import os
from pathlib import Path
import re
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/agriculture-scale"
CORE = FIXTURE / "core"
PROFILES = {
    1: ROOT / "tests/profiles/agriculture-scale-1-f210-2123.json",
    32: ROOT / "tests/profiles/agriculture-scale-32-f210-2123.json",
    128: ROOT / "tests/profiles/agriculture-scale-128-f210-2123.json",
}
ACTIVE_PROFILES = {
    arm: {
        tier: ROOT / "tests/profiles" / f"agriculture-active-matched-{arm}-{tier}-f210-2123.json"
        for tier in (1, 32, 128)
    }
    for arm in ("candidate-defaults", "published")
}
SCIENCE = [
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
    "cryogenic-science-pack", "military-science-pack", "utility-science-pack",
    "space-science-pack", "metallurgic-science-pack", "promethium-science-pack",
]
PUBLISHED_SCIENCE = [
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
    "cryogenic-science-pack",
]
PAIRED_PROFILES = {
    "candidate": ROOT / "tests/profiles/agriculture-paired-candidate-f210-2123.json",
    "published": ROOT / "tests/profiles/agriculture-paired-published-f210-2123.json",
}
PUBLISHED_ARCHIVE_SHA = "A4BB8F47232C689B267EF434F557187A8795C47280FA464169DE917FB579517F"
CANDIDATE_DEFAULT_ARCHIVE_SHA = "7B693B1715C46984AEC48EA84E7AA33D1A6ABFEBC36D1612BFF1B951B1227FB7"
OBSERVER_SHA = "2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C"
F210_RUNTIME_API_CANDIDATES = (
    os.environ.get("MIR_F210_RUNTIME_API"),
    "D:/Games/Steam/steamapps/common/Factorio/doc-html/runtime-api.json",
    "C:/Program Files/Steam/steamapps/common/Factorio/doc-html/runtime-api.json",
)
ENGINE_SHA = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"


def plain(value):
    if hasattr(value, "items"):
        return {key: plain(item) for key, item in value.items()}
    return value


def f210_runtime_api_path():
    for candidate in F210_RUNTIME_API_CANDIDATES:
        if candidate:
            path = Path(candidate)
            if path.is_file():
                return path
    return None


class AgricultureScaleFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().core_settings = (CORE / "settings.lua").as_posix()
        self.lua.globals().data_final = (CORE / "data-final-fixes.lua").as_posix()
        self.lua.globals().control = (CORE / "control.lua").as_posix()
        self.lua.globals().candidate_arm_settings = (FIXTURE / "arm-candidate" / "settings-updates.lua").as_posix()
        self.lua.globals().published_arm_settings = (FIXTURE / "arm-published" / "settings-updates.lua").as_posix()
        self.lua.globals().defaults_arm_settings = (FIXTURE / "arm-candidate-defaults" / "settings-updates.lua").as_posix()
        self.lua.execute(r'''
          function scale_data(selector_path, opponent, arm, matched_tier, active_seed)
            arm = arm or "legacy"
            local candidate_science = {
              "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
              "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
              "cryogenic-science-pack", "military-science-pack", "utility-science-pack",
              "space-science-pack", "metallurgic-science-pack", "promethium-science-pack"
            }
            local published_science = {
              "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
              "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
              "cryogenic-science-pack"
            }
            local science = (arm == "published" or arm == "candidate-defaults") and published_science or candidate_science
            local ingredients, prerequisites = {}, {}
            for index, name in ipairs(science) do
              ingredients[index], prerequisites[index] = {name, 1}, name
            end
            local technology = {
              level=1, max_level="infinite", upgrade=true,
              prerequisites=prerequisites,
              effects={{type="nothing", effect_description={
                "modifier-description.more-infinite-research.agricultural_growth_speed", "1"}}},
              unit={count_formula="40000*1.5^(L-1)", time=90, ingredients=ingredients}
            }
            if arm ~= "published" and arm ~= "candidate-defaults" then technology.enabled=true end
            if opponent == "formula" then technology.unit.count_formula = "broken" end
            if opponent == "time" then technology.unit.time = 91 end
            if opponent == "ingredient" then technology.unit.ingredients[#science] = {"broken-pack", 1} end
            if opponent == "ingredient-string" then technology.unit.ingredients[#science] = science[#science] end
            if opponent == "ingredient-missing-amount" then technology.unit.ingredients[#science] = {science[#science]} end
            if opponent == "prerequisite" then technology.prerequisites[#science] = "broken-prerequisite" end
            if opponent == "prerequisite-table" then technology.prerequisites[1] = {science[1], 1} end
            if opponent == "candidate-missing-gate" then technology.prerequisites[#science] = "space-science-pack" end
            if opponent == "candidate-duplicate-gate" then technology.prerequisites[#science + 1] = "promethium-science-pack" end
            if opponent == "effect" then technology.effects[1].effect_description[2] = "2" end
            if opponent == "candidate-disabled" then technology.enabled = false end
            if opponent == "published-enabled" then technology.enabled = true end
            if opponent == "published-hidden" then technology.hidden = false end
            local raw = {
              ["int-setting"] = {},
              ["string-setting"] = { ["mir-science-pack-ingredient-policy"]={setting_type="startup", default_value="configured"}},
              ["bool-setting"] = { ["ips-require-space-gate"]={setting_type="startup", default_value=false}},
              technology = {["recipe-prod-research_agricultural_growth_speed-1"]=technology},
              capsule = {yumako={spoil_ticks=216000, spoil_result="spoilage"}}
            }
            local active = {}
            if arm == "candidate" or arm == "published" or arm == "candidate-defaults" then
              active["mir-fixture-mir5-agriculture-scale-paired"] = "0.1.0"
              active["mir-fixture-mir5-agriculture-scale-arm-" .. arm] = "0.1.0"
            end
            if matched_tier then
              active["mir-fixture-mir5-agriculture-scale-matched-tier-" .. matched_tier] = "0.1.0"
            end
            if active_seed then
              active["mir-fixture-mir5-agriculture-scale-active"] = "0.1.0"
            end
            if opponent == "mixed-legacy-tier" then
              active["mir-fixture-mir5-agriculture-scale-tier-1"] = "0.1.0"
            end
            if opponent == "multiple-matched-tiers" then
              active["mir-fixture-mir5-agriculture-scale-matched-tier-32"] = "0.1.0"
              active["mir-fixture-mir5-agriculture-scale-matched-tier-128"] = "0.1.0"
            end
            if opponent == "zero-arm" then
              active["mir-fixture-mir5-agriculture-scale-paired"] = "0.1.0"
              active["mir-fixture-mir5-agriculture-scale-arm-candidate"] = nil
              active["mir-fixture-mir5-agriculture-scale-arm-published"] = nil
            end
            if opponent == "both-arm" then
              active["mir-fixture-mir5-agriculture-scale-paired"] = "0.1.0"
              active["mir-fixture-mir5-agriculture-scale-arm-candidate"] = "0.1.0"
              active["mir-fixture-mir5-agriculture-scale-arm-published"] = "0.1.0"
            end
            local data = {raw=raw}
            function data:extend(rows)
              for _, row in ipairs(rows) do raw[row.type][row.name] = row end
            end
            local env = {data=data, mods=active}
            setmetatable(env, {__index=_G})
            local settings_chunk = assert(loadfile(core_settings, "t", env))
            settings_chunk()
            if selector_path and selector_path ~= "" and not matched_tier then
              local selector_chunk = assert(loadfile(selector_path, "t", env))
              selector_chunk()
            end
            if arm == "candidate" then assert(loadfile(candidate_arm_settings, "t", env))() end
            if arm == "published" then assert(loadfile(published_arm_settings, "t", env))() end
            if arm == "candidate-defaults" then assert(loadfile(defaults_arm_settings, "t", env))() end
            if matched_tier then assert(loadfile(selector_path, "t", env))() end
            local selected_tier = raw["int-setting"]["mir5-agriculture-scale-tier"].default_value
            if opponent == "tier" then selected_tier = 2 end
            env.settings = {startup={
              ["mir5-agriculture-scale-tier"]={value=selected_tier},
              ["mir-science-pack-ingredient-policy"]={value=raw["string-setting"]["mir-science-pack-ingredient-policy"].default_value},
              ["ips-require-space-gate"]={value=raw["bool-setting"]["ips-require-space-gate"].default_value}
            }}
            if opponent == "settings-policy" then
              env.settings.startup["mir-science-pack-ingredient-policy"].value = "all-official"
            end
            if opponent == "settings-gate" then env.settings.startup["ips-require-space-gate"].value = true end
            local final_chunk = assert(loadfile(data_final, "t", env))
            local ok, message = pcall(final_chunk)
            return {ok=ok, message=tostring(message), raw=raw, selected_tier=selected_tier, active=active}
          end

          function parse_scale_control(path)
            local callbacks, reads = {events={}}, {}
            local env = {
              script = {
                on_init=function(callback) callbacks.init=callback end,
                on_load=function(callback) callbacks.load=callback end,
                on_event=function(event, callback) callbacks.events[event]=callback end,
                active_mods={}
              },
              defines={events={on_tick=1, on_research_finished=2, on_tower_planted_seed=3}, inventory={
                lab_input=1, agricultural_tower_input=2, chest=3
              }}
            }
            env._G = env
            setmetatable(env, {__index=function(_, key)
              if key == "game" or key == "storage" or key == "settings" then
                reads[key] = (reads[key] or 0) + 1
                error("control parse accessed " .. key)
              end
              return _G[key]
            end})
            local chunk, message = loadfile(path, "t", env)
            if not chunk then return {ok=false,message=message,reads=reads,callbacks=callbacks} end
            local ok, result = pcall(chunk)
            return {ok=ok,message=tostring(result),reads=reads,callbacks=callbacks}
          end

          function scale_runtime(path, tier, opponent, arm, matched, active_seed)
            arm = arm or "legacy"
            local candidate_packs = {
              "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
              "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
              "cryogenic-science-pack", "military-science-pack", "utility-science-pack",
              "space-science-pack", "metallurgic-science-pack", "promethium-science-pack"
            }
            local published_packs = {
              "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
              "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
              "cryogenic-science-pack"
            }
            local packs = (arm == "published" or arm == "candidate-defaults") and published_packs or candidate_packs
            local callbacks, reports, saves, save_names = {events={}}, {}, 0, {}
            local player, foreign
            local player_agriculture = {
              valid=true, name="recipe-prod-research_agricultural_growth_speed-1",
              level=1, researched=false, enabled=true, prerequisites={}, force=nil
            }
            player_agriculture.prerequisites = {
              {research_recursive=function() end}, {research_recursive=function() end}
            }
            player = {
              valid=true, name="player", index=1, technologies={
                ["recipe-prod-research_agricultural_growth_speed-1"]=player_agriculture
              }, current_research=nil
            }
            player_agriculture.force = player
            player.enable_all_prototypes=function() player.prototypes_enabled=true end
            player.get_spawn_position=function() return {x=0,y=0} end
            player.add_research=function(value)
              if player.current_research ~= nil or value ~= player_agriculture then return false end
              player.current_research=value
              return true
            end
            local lab_inventory = {counts={}}
            lab_inventory.insert=function(row)
              lab_inventory.counts[row.name]=(lab_inventory.counts[row.name] or 0)+row.count
              return row.count
            end
            lab_inventory.get_item_count=function(name) return lab_inventory.counts[name] or 0 end
            local lab = {valid=true, energy=0}
            lab.get_inventory=function(kind)
              assert(kind == 1)
              return lab_inventory
            end
            local towers, chests, next_unit, seed_inserts = {}, {}, 100, 0
            local surface = {generated=0, tile_count=0}
            surface.get_property=function(name) assert(name == "pressure"); return 1000 end
            surface.request_to_generate_chunks=function(center, radius)
              surface.generated, surface.generated_center = radius, center
            end
            surface.force_generate_chunk_requests=function() surface.generated_complete=true end
            surface.set_tiles=function(tiles) surface.tile_count=#tiles end
            surface.create_entity=function(row)
              if row.name == "lab" then return lab end
              if row.name == "agricultural-tower" then
                next_unit=next_unit+1
                local input = {}
                input.insert=function(seed)
                  assert(seed.name == "yumako-seed" and seed.count == 1)
                  seed_inserts = seed_inserts + 1
                  return 1
                end
                local tower={valid=true,name=row.name,force=row.force,unit_number=next_unit,energy=0}
                tower.get_inventory=function(kind) assert(kind == 2); return input end
                towers[#towers+1]=tower
                return tower
              end
              if row.name == "wooden-chest" then
                assert(math.abs(row.position.x - surface.generated_center.x) <= 32 * surface.generated
                  and math.abs(row.position.y - surface.generated_center.y) <= 32 * surface.generated,
                  "spoilage chest is outside the bounded generated region")
                local stack
                local inventory = {}
                inventory.insert=function(item)
                  assert(item.name == "yumako" and item.count == 1)
                  stack={valid_for_read=true,name="yumako",spoil_tick=216061,spoil_percent=0,
                    prototype={get_spoil_ticks=function() return 216000 end}}
                  inventory[1]=stack
                  return 1
                end
                local chest={valid=true,force=row.force}
                chest.get_inventory=function(kind) assert(kind == 3); return inventory end
                chests[#chests+1]=chest
                return chest
              end
              error("unexpected entity " .. tostring(row.name))
            end
            local active = {
              base="2.1.23", ["space-age"]="2.1.23",
              ["more-infinite-research"] = arm == "published" and "4.7.21002" or "5.0.21000",
              ["mir-fixture-mir5-agriculture-scale"]="0.1.0"
            }
            if arm == "candidate" or arm == "published" or arm == "candidate-defaults" then
              active["mir-fixture-mir5-agriculture-scale-paired"]="0.1.0"
              active["mir-fixture-mir5-agriculture-scale-arm-" .. arm]="0.1.0"
            else
              active["mir-fixture-mir5-agriculture-scale-tier-" .. tostring(tier)]="0.1.0"
            end
            if matched then
              active["mir-fixture-mir5-agriculture-scale-matched-tier-" .. tostring(tier)]="0.1.0"
            end
            if active_seed then
              active["mir-fixture-mir5-agriculture-scale-active"]="0.1.0"
            end
            if opponent == "mixed-legacy-tier" then
              active["mir-fixture-mir5-agriculture-scale-tier-1"]="0.1.0"
            end
            if opponent == "multiple-matched-tiers" then
              active["mir-fixture-mir5-agriculture-scale-matched-tier-32"]="0.1.0"
              active["mir-fixture-mir5-agriculture-scale-matched-tier-128"]="0.1.0"
            end
            if opponent == "zero-arm" then
              active["mir-fixture-mir5-agriculture-scale-paired"]="0.1.0"
              active["mir-fixture-mir5-agriculture-scale-arm-candidate"]=nil
              active["mir-fixture-mir5-agriculture-scale-arm-published"]=nil
            end
            if opponent == "both-arm" then
              active["mir-fixture-mir5-agriculture-scale-paired"]="0.1.0"
              active["mir-fixture-mir5-agriculture-scale-arm-candidate"]="0.1.0"
              active["mir-fixture-mir5-agriculture-scale-arm-published"]="0.1.0"
            end
            local env = {
              script={active_mods=active,
                on_init=function(callback) callbacks.init=callback end,
                on_load=function(callback) callbacks.load=callback end,
                on_event=function(event, callback) callbacks.events[event]=callback end},
              defines={events={on_tick=1,on_research_finished=2,on_tower_planted_seed=3},
                inventory={lab_input=1, agricultural_tower_input=2, chest=3}},
              settings={startup={
                ["mir5-agriculture-scale-tier"]={value=tier},
                ["mir-science-pack-ingredient-policy"]={value=arm == "candidate-defaults" and "configured" or "all-official"},
                ["ips-require-space-gate"]={value=arm ~= "candidate-defaults"},
                ["ips-enable-research_agricultural_growth_speed"]={value=true},
                ["ips-cost-base-research_agricultural_growth_speed"]={value=40000},
                ["ips-cost-linear-increment-research_agricultural_growth_speed"]={value=0},
                ["ips-cost-growth-research_agricultural_growth_speed"]={value=1.5},
                ["ips-max-level-research_agricultural_growth_speed"]={value=0},
                ["ips-research-time-research_agricultural_growth_speed"]={value=90},
                ["ips-effect-per-level-research_agricultural_growth_speed"]={value=1}
              }},
              storage={},
              helpers={
                table_to_json=function(row) reports[#reports+1]=row; return "fixture-json" end,
                create_profiler=function()
                  return setmetatable({valid=true, stop=function() end},
                    {__tostring=function() return "fixture-profiler" end})
                end
              },
              log=function() end
            }
            env.game = {
              tick=0, speed=1, forces={player=player}, surfaces={nauvis=surface},
              difficulty_settings={spoil_time_modifier=1},
              create_force=function(name)
                foreign={valid=true,name=name,index=2,technologies={},current_research=nil}
                local technology={valid=true,name="recipe-prod-research_agricultural_growth_speed-1",
                  level=1,researched=false,enabled=true,prerequisites={},force=foreign}
                foreign.technologies[technology.name]=technology
                foreign.enable_all_prototypes=function() foreign.prototypes_enabled=true end
                env.game.forces[name]=foreign
                env.game.forces[2]=foreign
                return foreign
              end,
              server_save=function(name)
                saves=saves+1
                save_names[#save_names+1]=name
              end
            }
            if opponent == "settings-policy" then
              env.settings.startup["mir-science-pack-ingredient-policy"].value = "all-official"
            end
            if opponent == "settings-gate" then env.settings.startup["ips-require-space-gate"].value = true end
            env._G=env
            setmetatable(env,{__index=function(_, key) return _G[key] end})
            local chunk, message=loadfile(path,"t",env)
            assert(chunk,message)
            local ok, message=pcall(chunk)
            if not ok then return {ok=false,message=tostring(message)} end
            ok, message=pcall(callbacks.init)
            if not ok then return {ok=false,message=tostring(message)} end

            local function complete_research()
              player.current_research=nil
              player_agriculture.level=player_agriculture.level+1
              return pcall(callbacks.events[2], {research=player_agriculture})
            end
            ok,message=complete_research()
            if not ok then return {ok=false,message=tostring(message)} end
            env.game.tick=60
            ok,message=pcall(callbacks.events[1])
            if not ok then return {ok=false,message=tostring(message)} end
            ok,message=complete_research()
            if not ok then return {ok=false,message=tostring(message)} end
            for _, name in ipairs(packs) do lab_inventory.counts[name]=14 end

            local state=env.storage.mir5_agriculture_scale
            if active_seed then
              if opponent == "active-early-event" then
                local tower=towers[1]
                local plant={valid=true,name="yumako-tree",force={index=3,name="neutral"},
                  prototype={growth_ticks=18000},tick_grown=env.game.tick+math.floor(18000/(1.01^2))}
                local result, failure=pcall(callbacks.events[3],
                  {tower=tower,plant=plant,seed={name="yumako-seed"},tick=env.game.tick})
                return {ok=result,message=tostring(failure),state=state,reports=reports,saves=saves,
                  save_names=save_names,seed_inserts=seed_inserts}
              end
              env.game.tick=60
              ok,message=pcall(callbacks.events[1])
              if not ok then return {ok=false,message=tostring(message),state=state} end
              if state.phase ~= "active-pending" or seed_inserts ~= 0 then
                return {ok=false,message="active fixture wrote seeds before load",state=state}
              end
              ok,message=pcall(callbacks.load)
              if not ok then return {ok=false,message=tostring(message),state=state} end
              ok,message=pcall(callbacks.events[1])
              if not ok then return {ok=false,message=tostring(message),state=state} end
            end
            if opponent == "bad-state" then
              state.phase="complete"
              local tower=towers[1]
              local plant={valid=true,name="yumako-tree",force=tower.force,
                prototype={growth_ticks=18000},tick_grown=env.game.tick+math.floor(18000/(1.01^2))}
              local result, failure=pcall(callbacks.events[3],
                {tower=tower,plant=plant,seed={name="yumako-seed"},tick=env.game.tick})
              return {ok=result,message=tostring(failure),state=state}
            end
            for index, tower in ipairs(towers) do
              local player_tower = tower.force.index == 1
              local remaining = player_tower and math.floor(18000/(1.01^2)) or 18000
              if opponent == "wrong-timing" and index == 1 then remaining=remaining+1 end
              if opponent == "wrong-force" and not player_tower then tower.force=player end
              local plant_force={index=3,name="neutral"}
              local plant={valid=true,name="yumako-tree",force=plant_force,
                prototype={growth_ticks=18000},tick_grown=env.game.tick+remaining}
              if opponent == "missing-event" and index == #towers then break end
              ok,message=pcall(callbacks.events[3], {tower=tower,plant=plant,seed={name="yumako-seed"},tick=env.game.tick})
              if not ok then return {ok=false,message=tostring(message),state=state} end
            end
            if opponent == "missing-event" then
              env.game.tick=state.deadline+1
              local result, failure=pcall(callbacks.events[1])
              return {ok=result,message=tostring(failure),state=state}
            end
            env.game.tick=61
            ok,message=pcall(callbacks.events[1])
            if not ok then return {ok=false,message=tostring(message),state=state} end

            if opponent == "load-repair" then state.planted_events=state.planted_events-1 end
            if opponent == "lost-consumption" then state.lab_consumption=nil end
            if opponent == "lost-tower" then towers[1].valid=false end
            local durable=state
            local original_storage=env.storage
            local read_only_state=setmetatable({}, {
              __index=function(_, key) return durable[key] end,
              __newindex=function() error("on_load wrote fixture state") end
            })
            local proxy=setmetatable({}, {
              __index=function(_, key)
                if key == "mir5_agriculture_scale" then return read_only_state end
                return original_storage[key]
              end,
              __newindex=function() error("on_load wrote fixture storage") end
            })
            env.storage=proxy
            ok,message=pcall(callbacks.load)
            if ok then ok,message=pcall(callbacks.events[1]) end
            env.storage=original_storage
            return {
              ok=ok,message=tostring(message),state=durable,reports=reports,saves=saves,towers=towers,
              save_names=save_names,seed_inserts=seed_inserts,chests=chests,surface=surface,player=player,foreign=foreign
            }
          end
        ''')
    def test_profiles_select_one_fixed_tier_and_exact_f210_closure(self):
        base = [
            ("base", "2.1.23"), ("elevated-rails", "2.1.23"), ("quality", "2.1.23"),
            ("recycler", "2.1.23"), ("space-age", "2.1.23"),
            ("more-infinite-research", "5.0.21000"),
            ("mir-fixture-mir5-agriculture-scale", "0.1.0"),
        ]
        core_info = json.loads((CORE / "info.json").read_text(encoding="utf-8-sig"))
        self.assertEqual(("mir-fixture-mir5-agriculture-scale", "0.1.0", "2.1"),
                         (core_info["name"], core_info["version"], core_info["factorio_version"]))
        self.assertEqual([
            "base = 2.1.23", "space-age = 2.1.23", "more-infinite-research >= 4.7.21002"
        ], core_info["dependencies"])
        for tier, profile_path in PROFILES.items():
            with self.subTest(legacy_tier=tier):
                profile = json.loads(profile_path.read_text(encoding="utf-8-sig"))
                selector = f"mir-fixture-mir5-agriculture-scale-tier-{tier}"
                actual = [(row["name"], row["version"]) for row in profile["mods"]]
                self.assertEqual(base + [(selector, "0.1.0"),
                                         ("mir-fixture-mir5-active-mods-observer", "0.1.0")], actual)
                self.assertEqual(("mir5-agriculture-scale-native-selection", "f210", "2.1",
                                  "2.1.23", ENGINE_SHA, "Defaults"),
                                 (profile["kind"], profile["target"], profile["factorio_line"],
                                  profile["engine"]["version"], profile["engine"]["sha256"],
                                  profile["settings_mode"]))
                self.assertIn(f"fixed {tier}-tower-per-force", profile["scope"])
                info = json.loads((FIXTURE / f"tier-{tier}" / "info.json").read_text(encoding="utf-8-sig"))
                self.assertEqual((selector, "0.1.0", "2.1"),
                                 (info["name"], info["version"], info["factorio_version"]))
                self.assertEqual(["base = 2.1.23", "mir-fixture-mir5-agriculture-scale >= 0.1.0"],
                                 info["dependencies"])

        official = [
            ("base", "2.1.23"), ("elevated-rails", "2.1.23"), ("quality", "2.1.23"),
            ("recycler", "2.1.23"), ("space-age", "2.1.23"),
        ]
        for arm, version in (("candidate", "5.0.21000"), ("published", "4.7.21002")):
            with self.subTest(paired_arm=arm):
                profile = json.loads(PAIRED_PROFILES[arm].read_text(encoding="utf-8-sig"))
                actual = [(row["name"], row["version"]) for row in profile["mods"]]
                self.assertEqual(official + [
                    ("more-infinite-research", version),
                    ("mir-fixture-mir5-agriculture-scale", "0.1.0"),
                    ("mir-fixture-mir5-agriculture-scale-paired", "0.1.0"),
                    (f"mir-fixture-mir5-agriculture-scale-arm-{arm}", "0.1.0"),
                    ("mir-fixture-mir5-active-mods-observer", "0.1.0"),
                ], actual)
                self.assertEqual(("mir5-agriculture-paired-native-selection", "f210", "2.1",
                                  "2.1.23", ENGINE_SHA, "Defaults"),
                                 (profile["kind"], profile["target"], profile["factorio_line"],
                                  profile["engine"]["version"], profile["engine"]["sha256"],
                                  profile["settings_mode"]))
                self.assertIn("two real labs", profile["scope"])
                self.assertIn("performance", profile["scope"])
                if arm == "published":
                    self.assertEqual({
                        "more-infinite-research_4.7.21002.zip": PUBLISHED_ARCHIVE_SHA,
                        "mir-fixture-mir5-active-mods-observer_0.1.0.zip": OBSERVER_SHA,
                    }, profile["archive_sha256"])
                    self.assertIn("seven-science/raw-omission", profile["scope"])
                else:
                    self.assertNotIn("archive_sha256", profile)
                    self.assertIn("twelve-science", profile["scope"])

        candidate_default = json.loads((ROOT / "tests/profiles/agriculture-candidate-default-f210-2123.json")
                                       .read_text(encoding="utf-8-sig"))
        self.assertEqual(("mir5-agriculture-candidate-default-f210-prototype-capture-selection",
                          "f210", "2.1", "2.1.23", ENGINE_SHA, "Defaults"),
                         (candidate_default["kind"], candidate_default["target"],
                          candidate_default["factorio_line"], candidate_default["engine"]["version"],
                          candidate_default["engine"]["sha256"], candidate_default["settings_mode"]))
        self.assertEqual(official + [("mir-fixture-mir5-active-mods-observer", "0.1.0")],
                         [(row["name"], row["version"]) for row in candidate_default["mods"]])
        self.assertEqual({
            "more-infinite-research_5.0.21000.zip": CANDIDATE_DEFAULT_ARCHIVE_SHA,
            "mir-fixture-mir5-active-mods-observer_0.1.0.zip": OBSERVER_SHA,
        }, candidate_default["archive_sha256"])
        self.assertIn("no agriculture core, paired arm, policy selector", candidate_default["scope"].lower())
        self.assertFalse(any(row["name"].startswith("mir-fixture-mir5-agriculture")
                             for row in candidate_default["mods"]))

        paired_info = json.loads((FIXTURE / "paired" / "info.json").read_text(encoding="utf-8-sig"))
        self.assertEqual(["base = 2.1.23", "mir-fixture-mir5-agriculture-scale >= 0.1.0"],
                         paired_info["dependencies"])
        for arm, version in (("candidate", "5.0.21000"), ("published", "4.7.21002")):
            arm_root = FIXTURE / f"arm-{arm}"
            info = json.loads((arm_root / "info.json").read_text(encoding="utf-8-sig"))
            self.assertEqual(["base = 2.1.23", f"more-infinite-research = {version}",
                              "mir-fixture-mir5-agriculture-scale-paired >= 0.1.0"],
                             info["dependencies"])
            self.assertTrue((arm_root / "settings-updates.lua").is_file())
            self.assertFalse((arm_root / "control.lua").exists())
        self.assertTrue((FIXTURE / "paired" / "settings-updates.lua").is_file())
        self.assertFalse((FIXTURE / "paired" / "control.lua").exists())
        self.assertEqual([CORE / "control.lua"], list(FIXTURE.glob("*/control.lua")))

    def test_selector_and_data_preflight_accept_only_fixed_authored_tiers(self):
        run = self.lua.eval("scale_data")
        for tier in PROFILES:
            with self.subTest(legacy_tier=tier):
                result = plain(run((FIXTURE / f"tier-{tier}" / "settings-updates.lua").as_posix(), ""))
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(tier, result["selected_tier"])
                raw = result["raw"]
                self.assertEqual(tier, raw["int-setting"]["mir5-agriculture-scale-tier"]["default_value"])
                self.assertEqual("all-official",
                                 raw["string-setting"]["mir-science-pack-ingredient-policy"]["default_value"])
                self.assertTrue(raw["bool-setting"]["ips-require-space-gate"]["default_value"])
                agriculture = raw["technology"]["recipe-prod-research_agricultural_growth_speed-1"]
                self.assertEqual((1, None, 1),
                                 (agriculture["unit"].get("count"), agriculture["unit"].get("count_formula"),
                                  agriculture["unit"]["time"]))
        selector = (FIXTURE / "tier-1" / "settings-updates.lua").as_posix()
        for opponent, expected in (("formula", "default agricultural research tuning"),
                                   ("time", "default agricultural research tuning"),
                                   ("ingredient", "science vector differs"),
                                   ("prerequisite", "candidate promethium prerequisite gate differs"),
                                   ("effect", "effect contract differs"),
                                   ("tier", "not an authored fixed tier")):
            with self.subTest(legacy_opponent=opponent):
                result = plain(run(selector, opponent))
                self.assertFalse(result["ok"])
                self.assertIn(expected, result["message"])
                agriculture = result["raw"]["technology"]["recipe-prod-research_agricultural_growth_speed-1"]
                self.assertEqual(91 if opponent == "time" else 90, agriculture["unit"]["time"])
                self.assertIsNone(agriculture["unit"].get("count"))

    def test_paired_data_preflight_binds_independent_science_arms_and_refuses_ambiguous_selection(self):
        run = self.lua.eval("scale_data")
        selector = (FIXTURE / "paired" / "settings-updates.lua").as_posix()
        for arm, science in (("candidate", SCIENCE), ("published", PUBLISHED_SCIENCE)):
            with self.subTest(arm=arm):
                result = plain(run(selector, "", arm))
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(1, result["selected_tier"])
                technology = result["raw"]["technology"]["recipe-prod-research_agricultural_growth_speed-1"]
                self.assertEqual(science, [row[1] for row in technology["unit"]["ingredients"].values()])
                if arm == "published":
                    self.assertEqual(PUBLISHED_SCIENCE,
                                     [row for row in technology["prerequisites"].values()])
                else:
                    self.assertEqual(1, [row for row in technology["prerequisites"].values()]
                                     .count("promethium-science-pack"))
                self.assertEqual((1, None, 1),
                                 (technology["unit"].get("count"), technology["unit"].get("count_formula"),
                                  technology["unit"]["time"]))
                if arm == "candidate":
                    self.assertTrue(technology["enabled"])
                    self.assertEqual("all-official", result["raw"]["string-setting"]
                                     ["mir-science-pack-ingredient-policy"]["default_value"])
                    self.assertTrue(result["raw"]["bool-setting"]["ips-require-space-gate"]["default_value"])
                else:
                    self.assertNotIn("enabled", technology)
                    self.assertNotIn("hidden", technology)

        for arm, opponent, expected in (
            ("candidate", "formula", "default agricultural research tuning"),
            ("candidate", "time", "default agricultural research tuning"),
            ("candidate", "ingredient", "science vector differs"),
            ("candidate", "ingredient-string", "science vector row is not a table"),
            ("candidate", "ingredient-missing-amount", "science vector differs"),
            ("candidate", "candidate-missing-gate", "promethium prerequisite gate differs"),
            ("candidate", "candidate-duplicate-gate", "promethium prerequisite gate differs"),
            ("candidate", "prerequisite-table", "candidate-mir5 prerequisite is not a string"),
            ("candidate", "effect", "effect contract differs"),
            ("candidate", "candidate-disabled", "must not be disabled"),
            ("published", "ingredient", "science vector differs"),
            ("published", "ingredient-string", "science vector row is not a table"),
            ("published", "ingredient-missing-amount", "science vector differs"),
            ("published", "prerequisite", "prerequisite vector differs"),
            ("published", "prerequisite-table", "prerequisite vector differs"),
            ("published", "effect", "effect contract differs"),
            ("published", "published-enabled", "enabled/hidden omission"),
            ("published", "published-hidden", "enabled/hidden omission"),
            ("candidate", "zero-arm", "exactly one arm selector"),
            ("candidate", "both-arm", "exactly one arm selector"),
        ):
            with self.subTest(arm=arm, opponent=opponent):
                result = plain(run(selector, opponent, arm))
                self.assertFalse(result["ok"])
                technology = result["raw"]["technology"]["recipe-prod-research_agricultural_growth_speed-1"]
                self.assertEqual(91 if opponent == "time" else 90, technology["unit"]["time"])
                self.assertEqual("broken" if opponent == "formula" else "40000*1.5^(L-1)",
                                 technology["unit"].get("count_formula"))
                self.assertIsNone(technology["unit"].get("count"))
                self.assertIn(expected, result["message"])

    def test_control_registers_before_native_state_and_imports_nothing(self):
        parsed = plain(self.lua.eval("parse_scale_control")(str(CORE / "control.lua")))
        self.assertTrue(parsed["ok"], parsed["message"])
        self.assertEqual({}, parsed["reads"])
        self.assertEqual({"init", "load"}, set(key for key in parsed["callbacks"] if key != "events"))
        self.assertEqual({1, 2, 3}, set(parsed["callbacks"]["events"]))
        source = (CORE / "control.lua").read_text(encoding="utf-8-sig")
        for token in ("force.add_research", "on_research_finished", "on_tower_planted_seed",
                      "helpers.create_profiler", "spoil_tick", "game.server_save(SAVE)"):
            with self.subTest(token=token):
                self.assertIn(token, source)
        for token in ("require(", "storage.mir", "script.raise_event"):
            with self.subTest(forbidden=token):
                self.assertNotIn(token, source)
        self.assertNotRegex(source, r"(?:event\.plant|plants?\[[^]]+\]\.plant)\.tick_grown\s*=(?!=)")
        self.assertNotRegex(source, r"\.level\s*=(?!=)")
        self.assertNotRegex(source, r"\.researched\s*=(?!=)")

    def test_host_observer_requires_exact_events_timing_force_state_and_read_only_reload(self):
        run = self.lua.eval("scale_runtime")
        for tier in PROFILES:
            with self.subTest(tier=tier):
                result = run(str(CORE / "control.lua"), tier, "")
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(1, result["saves"])
                self.assertEqual(2 * tier, len(result["towers"]))
                self.assertEqual(4, len(result["chests"]))
                self.assertEqual(2 * tier * 121, result["surface"]["tile_count"])
                self.assertGreaterEqual(result["surface"]["generated"], 1)
                self.assertLessEqual(result["surface"]["generated"], 8)
                self.assertEqual(3, result["player"]["technologies"]
                                 ["recipe-prod-research_agricultural_growth_speed-1"]["level"])
                self.assertEqual(1, result["foreign"]["technologies"]
                                 ["recipe-prod-research_agricultural_growth_speed-1"]["level"])
                stages = [result["reports"][index]["stage"]
                          for index in range(1, len(result["reports"]) + 1)]
                self.assertEqual(["initial", "reload"], stages)
                witness = result["reports"][2]["witnesses"]
                self.assertEqual(tier, witness["tier"])
                self.assertEqual({"expected": 2 * tier, "observed": 2 * tier},
                                 plain(witness["native_planting_events"]))
                self.assertEqual("not-evaluated", witness["profiler_timing_decision"])
                self.assertEqual("unresolved", witness["published_4_7_contract"])
                self.assertTrue(witness["cold_reload_witness"])
                self.assertTrue(witness["on_load_read_only"])

        for opponent, expected in (
            ("wrong-timing", "native planted growth timing differs"),
            ("wrong-force", "native tower event owner or plant contract differs"),
            ("missing-event", "did not satisfy the fixed-tier deadline"),
            ("bad-state", "outside planting state"),
            ("load-repair", "native planted event count differs"),
            ("lost-consumption", "saved lab consumption witness is absent"),
            ("lost-tower", "native tower witness differs"),
        ):
            with self.subTest(opponent=opponent):
                result = run(str(CORE / "control.lua"), 1, opponent)
                self.assertFalse(result["ok"])
                self.assertIn(expected, result["message"])

    def test_paired_arms_share_physical_crop_protocol_without_claiming_definition_equality(self):
        run = self.lua.eval("scale_runtime")
        for arm, science, published_contract in (
            ("candidate", SCIENCE, "not-selected"),
            ("published", PUBLISHED_SCIENCE, "independently-captured-95B1A1FC-27FBC90D"),
        ):
            with self.subTest(arm=arm):
                result = run(str(CORE / "control.lua"), 1, "", arm)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(1, result["saves"])
                self.assertEqual(2, len(result["towers"]))
                self.assertEqual(4, len(result["chests"]))
                self.assertEqual(3, result["player"]["technologies"]
                                 ["recipe-prod-research_agricultural_growth_speed-1"]["level"])
                self.assertEqual(1, result["foreign"]["technologies"]
                                 ["recipe-prod-research_agricultural_growth_speed-1"]["level"])
                state = result["state"]
                self.assertTrue(state["paired"])
                self.assertEqual("candidate-mir5" if arm == "candidate" else "published-4.7.21002",
                                 state["arm"])
                reports = [result["reports"][index] for index in range(1, len(result["reports"]) + 1)]
                self.assertEqual(["initial", "reload"], [row["stage"] for row in reports])
                witness = reports[-1]["witnesses"]
                self.assertEqual(science, [witness["science_contract"]["packs"][index]
                                           for index in range(1, len(science) + 1)])
                self.assertEqual(published_contract, witness["published_4_7_contract"])
                self.assertTrue(witness["cold_reload_witness"])
                self.assertTrue(witness["on_load_read_only"])
                self.assertEqual(2, state["research_finished"])
                self.assertEqual(2, state["planted_events"])
                self.assertEqual(set(science), set(plain(state["lab_consumption"])))

        for opponent in ("zero-arm", "both-arm"):
            with self.subTest(opponent=opponent):
                result = run(str(CORE / "control.lua"), 1, opponent, "candidate")
                self.assertFalse(result["ok"])
                self.assertIn("exactly one arm selector", result["message"])

    def test_matched_defaults_profiles_use_neutral_tiers_and_exact_arm_closures(self):
        for tier in (1, 32, 128):
            selector_name = f"mir-fixture-mir5-agriculture-scale-matched-tier-{tier}"
            selector_info = json.loads((FIXTURE / f"matched-tier-{tier}" / "info.json").read_text())
            self.assertEqual(selector_name, selector_info["name"])
            self.assertEqual([
                "base = 2.1.23", "mir-fixture-mir5-agriculture-scale-paired >= 0.1.0",
                "? mir-fixture-mir5-agriculture-scale-arm-candidate-defaults >= 0.1.0",
                "? mir-fixture-mir5-agriculture-scale-arm-published >= 0.1.0",
            ], selector_info["dependencies"])
            for arm, version in (("candidate-defaults", "5.0.21000"), ("published", "4.7.21002")):
                with self.subTest(tier=tier, arm=arm):
                    profile = json.loads((ROOT / "tests/profiles" /
                        f"agriculture-matched-{arm}-{tier}-f210-2123.json").read_text())
                    self.assertEqual("mir5-agriculture-matched-defaults-native-selection", profile["kind"])
                    self.assertEqual({"version": "2.1.23", "sha256": ENGINE_SHA}, profile["engine"])
                    self.assertEqual("Defaults", profile["settings_mode"])
                    self.assertEqual([
                        ("base", "2.1.23"), ("elevated-rails", "2.1.23"), ("quality", "2.1.23"),
                        ("recycler", "2.1.23"), ("space-age", "2.1.23"),
                        ("more-infinite-research", version), ("mir-fixture-mir5-agriculture-scale", "0.1.0"),
                        ("mir-fixture-mir5-agriculture-scale-paired", "0.1.0"),
                        (f"mir-fixture-mir5-agriculture-scale-arm-{arm}", "0.1.0"),
                        (selector_name, "0.1.0"), ("mir-fixture-mir5-active-mods-observer", "0.1.0"),
                    ], [(row["name"], row["version"]) for row in profile["mods"]])
                    self.assertTrue(all(row["enabled"] for row in profile["mods"]))
                    expected_archives = {"mir-fixture-mir5-active-mods-observer_0.1.0.zip": OBSERVER_SHA}
                    if arm == "published":
                        expected_archives["more-infinite-research_4.7.21002.zip"] = PUBLISHED_ARCHIVE_SHA
                    self.assertEqual(expected_archives, profile["archive_sha256"])

        active_info = json.loads((FIXTURE / "active" / "info.json").read_text())
        self.assertEqual(
            ("mir-fixture-mir5-agriculture-scale-active", "0.1.0", "2.1"),
            (active_info["name"], active_info["version"], active_info["factorio_version"]),
        )
        self.assertEqual([
            "base = 2.1.23", "mir-fixture-mir5-agriculture-scale-paired >= 0.1.0",
        ], active_info["dependencies"])
        for tier in (1, 32, 128):
            for arm, version, archive in (
                ("candidate-defaults", "5.0.21000", "428A789CA03828D2F7F93EC65C49FD3157FD6D547CC569DDA2C0129D6504647A"),
                ("published", "4.7.21002", PUBLISHED_ARCHIVE_SHA),
            ):
                with self.subTest(active_tier=tier, active_arm=arm):
                    profile = json.loads(ACTIVE_PROFILES[arm][tier].read_text())
                    self.assertEqual("mir5-active-agriculture-native-selection", profile["kind"])
                    self.assertEqual({"version": "2.1.23", "sha256": ENGINE_SHA}, profile["engine"])
                    self.assertEqual("Defaults", profile["settings_mode"])
                    self.assertEqual([
                        ("base", "2.1.23"), ("elevated-rails", "2.1.23"), ("quality", "2.1.23"),
                        ("recycler", "2.1.23"), ("space-age", "2.1.23"),
                        ("more-infinite-research", version), ("mir-fixture-mir5-agriculture-scale", "0.1.0"),
                        ("mir-fixture-mir5-agriculture-scale-paired", "0.1.0"),
                        (f"mir-fixture-mir5-agriculture-scale-arm-{arm}", "0.1.0"),
                        (f"mir-fixture-mir5-agriculture-scale-matched-tier-{tier}", "0.1.0"),
                        ("mir-fixture-mir5-agriculture-scale-active", "0.1.0"),
                        ("mir-fixture-mir5-active-mods-observer", "0.1.0"),
                    ], [(row["name"], row["version"]) for row in profile["mods"]])
                    self.assertEqual(archive, profile["archive_sha256"]
                                     [f"more-infinite-research_{version}.zip"])

    def test_matched_defaults_data_preflight_keeps_seven_captured_packs_and_product_defaults(self):
        run = self.lua.eval("scale_data")
        for tier in (1, 32, 128):
            selector = (FIXTURE / f"matched-tier-{tier}" / "settings-updates.lua").as_posix()
            for arm in ("candidate-defaults", "published"):
                with self.subTest(tier=tier, arm=arm):
                    result = plain(run(selector, "", arm, tier))
                    self.assertTrue(result["ok"], result["message"])
                    self.assertEqual(tier, result["selected_tier"])
                    raw = result["raw"]
                    technology = raw["technology"]["recipe-prod-research_agricultural_growth_speed-1"]
                    self.assertEqual(PUBLISHED_SCIENCE,
                                     list(technology["prerequisites"].values()))
                    self.assertEqual(PUBLISHED_SCIENCE,
                                     [row[1] for row in technology["unit"]["ingredients"].values()])
                    self.assertNotIn("enabled", technology)
                    self.assertNotIn("hidden", technology)
                    self.assertEqual((1, None, 1), (technology["unit"]["count"],
                        technology["unit"].get("count_formula"), technology["unit"]["time"]))
                    self.assertEqual("configured", raw["string-setting"]
                                     ["mir-science-pack-ingredient-policy"]["default_value"])
                    self.assertFalse(raw["bool-setting"]["ips-require-space-gate"]["default_value"])

        selector = (FIXTURE / "matched-tier-1" / "settings-updates.lua").as_posix()
        for opponent in ("ingredient", "prerequisite", "published-enabled", "published-hidden",
                         "settings-policy", "settings-gate", "mixed-legacy-tier", "multiple-matched-tiers"):
            with self.subTest(opponent=opponent):
                result = plain(run(selector, opponent, "candidate-defaults", 1))
                self.assertFalse(result["ok"])
                technology = result["raw"]["technology"]["recipe-prod-research_agricultural_growth_speed-1"]
                self.assertEqual("40000*1.5^(L-1)", technology["unit"]["count_formula"])
                self.assertEqual(90, technology["unit"]["time"])
                self.assertNotIn("count", technology["unit"])
        forced = plain(run(selector, "", "candidate", 1))
        self.assertFalse(forced["ok"])
        self.assertIn("require Defaults or published arm", forced["message"])
        no_tier = plain(run((FIXTURE / "paired" / "settings-updates.lua").as_posix(), "", "candidate-defaults"))
        self.assertFalse(no_tier["ok"])
        self.assertIn("requires a matched tier selector", no_tier["message"])

        active = plain(run(selector, "", "candidate-defaults", 1, True))
        self.assertTrue(active["ok"], active["message"])
        self.assertEqual(1, active["selected_tier"])
        active_without_tier = plain(run((FIXTURE / "paired" / "settings-updates.lua").as_posix(), "",
                                        "candidate-defaults", None, True))
        self.assertFalse(active_without_tier["ok"])
        self.assertIn("active fixture requires exactly one matched tier selector", active_without_tier["message"])

    def test_matched_defaults_runtime_shares_two_lab_levels_native_growth_spoilage_and_read_only_load(self):
        run = self.lua.eval("scale_runtime")
        for tier in (1, 32, 128):
            for arm in ("candidate-defaults", "published"):
                with self.subTest(tier=tier, arm=arm):
                    result = run(str(CORE / "control.lua"), tier, "", arm, True)
                    self.assertTrue(result["ok"], result["message"])
                    self.assertEqual(1, result["saves"])
                    self.assertEqual(2 * tier, len(result["towers"]))
                    self.assertEqual(4, len(result["chests"]))
                    state = result["state"]
                    self.assertEqual("candidate-defaults-mir5" if arm == "candidate-defaults"
                                     else "published-4.7.21002", state["arm"])
                    self.assertEqual(2, state["research_finished"])
                    self.assertEqual(2 * tier, state["planted_events"])
                    self.assertEqual(set(PUBLISHED_SCIENCE), set(plain(state["lab_consumption"])))
                    reports = list(plain(result["reports"]).values())
                    self.assertEqual(["initial", "reload"], [row["stage"] for row in reports])
                    witness = reports[-1]["witnesses"]
                    self.assertEqual(PUBLISHED_SCIENCE, list(witness["science_contract"]["packs"].values()))
                    self.assertEqual(17645, witness["trained_remaining_ticks"])
                    self.assertEqual(18000, witness["foreign_remaining_ticks"])
                    self.assertTrue(witness["cold_reload_witness"])
                    self.assertTrue(witness["on_load_read_only"])
                    self.assertFalse(witness["ordinary_tuning_qualified"])

        for opponent in ("settings-policy", "settings-gate", "mixed-legacy-tier", "multiple-matched-tiers",
                         "wrong-timing", "wrong-force", "lost-tower", "load-repair", "lost-consumption"):
            with self.subTest(opponent=opponent):
                result = run(str(CORE / "control.lua"), 1, opponent, "candidate-defaults", True)
                self.assertFalse(result["ok"])

    def test_active_matched_profiles_defer_real_seed_events_until_after_load(self):
        run = self.lua.eval("scale_runtime")
        for tier in (1, 32, 128):
            for arm in ("candidate-defaults", "published"):
                with self.subTest(tier=tier, arm=arm):
                    result = run(str(CORE / "control.lua"), tier, "", arm, True, True)
                    self.assertTrue(result["ok"], result["message"])
                    self.assertEqual(2, result["saves"])
                    self.assertEqual(["mir5-native-active", "mir5-native-complete"],
                                     [result["save_names"][index]
                                      for index in range(1, len(result["save_names"]) + 1)])
                    self.assertEqual(2 * tier, result["seed_inserts"])
                    self.assertEqual(2 * tier, result["state"]["planted_events"])
                    reports = list(plain(result["reports"]).values())
                    self.assertEqual(["prepared", "start", "complete", "initial", "reload"],
                                     [row["stage"] for row in reports])
                    self.assertEqual(0, reports[1]["witnesses"]["native_planting_events"]["observed"])
                    self.assertEqual(2 * tier,
                                     reports[2]["witnesses"]["native_planting_events"]["observed"])
                    self.assertTrue(reports[1]["witnesses"]["pending_physical_work"])
                    self.assertFalse(reports[2]["witnesses"]["pending_physical_work"])

        early = run(str(CORE / "control.lua"), 1, "active-early-event", "candidate-defaults", True, True)
        self.assertFalse(early["ok"])
        self.assertIn("outside planting state", early["message"])
        unpaired = run(str(CORE / "control.lua"), 1, "", "legacy", False, True)
        self.assertFalse(unpaired["ok"])
        self.assertIn("requires the paired selector", unpaired["message"])

    def test_exact_f210_api_declares_the_fixture_runtime_surface(self):
        api_path = f210_runtime_api_path()
        if api_path is None:
            self.skipTest("F210 runtime API documentation is not installed on this host")
        document = json.loads(api_path.read_text(encoding="utf-8"))
        event = next(row for row in document["events"] if row["name"] == "on_tower_planted_seed")
        self.assertEqual({"name", "tower", "plant", "seed", "tick"},
                         {row["name"] for row in event["data"]})
        self.assertEqual("ItemIDAndQualityIDPair",
                         next(row["type"] for row in event["data"] if row["name"] == "seed"))
        seed_pair = next(row for row in document["concepts"] if row["name"] == "ItemIDAndQualityIDPair")
        self.assertEqual("name", seed_pair["type"]["parameters"][0]["name"])
        classes = {row["name"]: row for row in document["classes"]}
        entity = {row["name"]: row for row in classes["LuaEntity"]["attributes"]}
        stack = {row["name"]: row for row in classes["LuaItemStack"]["attributes"]}
        item_methods = {row["name"]: row for row in classes["LuaItemPrototype"]["methods"]}
        surface_methods = {row["name"]: row for row in classes["LuaSurface"]["methods"]}
        helper_methods = {row["name"]: row for row in classes["LuaHelpers"]["methods"]}
        self.assertEqual("MapTick", entity["tick_grown"]["read_type"])
        self.assertEqual("MapTick", entity["tick_grown"]["write_type"])
        self.assertEqual("MapTick", stack["spoil_tick"]["read_type"])
        self.assertEqual("MapTick", stack["spoil_tick"]["write_type"])
        self.assertEqual("double", stack["spoil_percent"]["read_type"])
        self.assertEqual("uint32", item_methods["get_spoil_ticks"]["return_values"][0]["type"])
        self.assertEqual("LuaProfiler", helper_methods["create_profiler"]["return_values"][0]["type"])
        self.assertEqual("stopped", helper_methods["create_profiler"]["parameters"][0]["name"])
        for name in ("request_to_generate_chunks", "force_generate_chunk_requests", "set_tiles",
                     "create_entity", "get_property"):
            self.assertIn(name, surface_methods)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(AgricultureScaleFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)
