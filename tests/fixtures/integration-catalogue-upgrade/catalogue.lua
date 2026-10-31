-- Private F200 published-row projection recovered mechanically from Black Glass
-- run 40051640723.  It is fixture data, not player source: the lists make the
-- save witness explicit and do not discover arbitrary technology families.
return {
  provenance = {
    run = "40051640723",
    published_mir = "4.7.20002",
    engine = "2.0.77",
    source = "published data-raw-dump exact rows mechanically recovered before fixture authoring"
  },
  force_fields = {
    "train_braking_force_bonus",
    "inserter_stack_size_bonus",
    "bulk_inserter_capacity_bonus",
    "laboratory_speed_modifier",
    "laboratory_productivity_bonus",
    "worker_robots_storage_bonus",
    "manual_crafting_speed_modifier",
    "manual_mining_speed_modifier",
    "character_reach_distance_bonus",
    "character_build_distance_bonus",
    "character_resource_reach_distance_bonus",
    "character_item_drop_distance_bonus",
    "character_running_speed_modifier",
    "character_inventory_slots_bonus",
    "character_trash_slot_count",
    "worker_robots_battery_modifier"
  },
  profiles = {
    ["armor-bobwarfare"] = {
      requires = {
        boblibrary = "2.1.0",
        bobwarfare = "2.1.0"
      },
      public = {
        "braking-force-8",
        "inserter-capacity-bonus-8",
        "laser-shooting-speed-8",
        "recipe-prod-research_advanced_circuit-1",
        "recipe-prod-research_armor_components-1",
        "recipe-prod-research_batteries-1",
        "recipe-prod-research_belts-1",
        "recipe-prod-research_bullets-1",
        "recipe-prod-research_cannon_shooting_speed-1",
        "recipe-prod-research_character_crafting_speed-1",
        "recipe-prod-research_character_mining_speed-1",
        "recipe-prod-research_character_reach-1",
        "recipe-prod-research_character_walking_speed-1",
        "recipe-prod-research_concrete-1",
        "recipe-prod-research_copper-1",
        "recipe-prod-research_copper_cable-1",
        "recipe-prod-research_electric_energy-1",
        "recipe-prod-research_electric_engine-1",
        "recipe-prod-research_electric_shooting_speed-1",
        "recipe-prod-research_electronic_circuit-1",
        "recipe-prod-research_engine-1",
        "recipe-prod-research_explosives-1",
        "recipe-prod-research_flamethrower_shooting_speed-1",
        "recipe-prod-research_flying_robot_frame-1",
        "recipe-prod-research_furnace-1",
        "recipe-prod-research_gears-1",
        "recipe-prod-research_grenades-1",
        "recipe-prod-research_heavy_ammo-1",
        "recipe-prod-research_inserters-1",
        "recipe-prod-research_inventory_capacity-1",
        "recipe-prod-research_iron-1",
        "recipe-prod-research_iron_sticks-1",
        "recipe-prod-research_lab_productivity-1",
        "recipe-prod-research_landfill-1",
        "recipe-prod-research_low_density_structure-1",
        "recipe-prod-research_lubricant_productivity-1",
        "recipe-prod-research_mining_drill-1",
        "recipe-prod-research_modules-1",
        "recipe-prod-research_oil_cracking_productivity-1",
        "recipe-prod-research_oil_processing_productivity-1",
        "recipe-prod-research_plastic-1",
        "recipe-prod-research_processing_unit-1",
        "recipe-prod-research_rails-1",
        "recipe-prod-research_robot_battery-1",
        "recipe-prod-research_rocket_fuel-1",
        "recipe-prod-research_rocket_shooting_speed-1",
        "recipe-prod-research_rockets-1",
        "recipe-prod-research_science_pack_productivity-1",
        "recipe-prod-research_steel-1",
        "recipe-prod-research_sulfur-1",
        "recipe-prod-research_sulfuric_acid_productivity-1",
        "recipe-prod-research_walls-1",
        "research-speed-7",
        "weapon-shooting-speed-7",
        "worker-robots-storage-4"
      },
      primary = "recipe-prod-research_armor_components-1",
      continuation = "laser-shooting-speed-8",
      finite = nil,
      preflight_names = {
        "recipe-prod-research_armor_components-1",
        "laser-shooting-speed-8"
      },
      preflight = {
        ["recipe-prod-research_armor_components-1"] = {
          name = "recipe-prod-research_armor_components-1",
          localised_name = {
            "technology-name.more-infinite-research.research_armor_components",
            {
              "technology-name.power-armor"
            }
          },
          localised_description = {
            "technology-description.more-infinite-research.recipe_productivity"
          },
          icons = {
            {
              icon = "__base__/graphics/technology/power-armor.png",
              icon_size = 256
            },
            {
              icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
              icon_size = 128,
              scale = 0.5,
              shift = {
                50,
                50
              },
              floating = true
            }
          },
          effects = {
            {
              type = "change-recipe-productivity",
              recipe = "bob-mech-armor-plate",
              change = 0.02
            }
          },
          prerequisites = {
            "automation-science-pack",
            "logistic-science-pack",
            "chemical-science-pack",
            "production-science-pack",
            "military-science-pack"
          },
          unit = {
            ingredients = {
              {
                "automation-science-pack",
                1
              },
              {
                "logistic-science-pack",
                1
              },
              {
                "chemical-science-pack",
                1
              },
              {
                "production-science-pack",
                1
              },
              {
                "military-science-pack",
                1
              }
            },
            count_formula = "8000*2^(L-1)",
            time = 60
          },
          max_level = "infinite",
          order = "p[research_armor_components]",
          level = 1,
          upgrade = true,
          type = "technology"
        },
        ["laser-shooting-speed-8"] = {
          name = "laser-shooting-speed-8",
          localised_name = {
            "technology-name.laser-shooting-speed"
          },
          localised_description = {
            "technology-description.laser-shooting-speed"
          },
          icons = {
            {
              icon = "__base__/graphics/technology/laser-shooting-speed.png",
              icon_size = 256
            },
            {
              icon = "__core__/graphics/icons/technology/constants/constant-speed.png",
              icon_size = 128,
              scale = 0.5,
              shift = {
                50,
                50
              },
              floating = true
            }
          },
          effects = {
            {
              type = "gun-speed",
              ammo_category = "laser",
              modifier = 0.5
            },
            {
              type = "gun-speed",
              ammo_category = "bob-laser-rifle",
              modifier = 0.5
            }
          },
          prerequisites = {
            "laser-shooting-speed-6",
            "laser-shooting-speed-7",
            "automation-science-pack",
            "logistic-science-pack",
            "chemical-science-pack",
            "military-science-pack",
            "utility-science-pack"
          },
          unit = {
            ingredients = {
              {
                "automation-science-pack",
                1
              },
              {
                "logistic-science-pack",
                1
              },
              {
                "chemical-science-pack",
                1
              },
              {
                "military-science-pack",
                1
              },
              {
                "utility-science-pack",
                1
              }
            },
            count_formula = "1025.15625*1.5^(L-8)",
            time = 120
          },
          max_level = "infinite",
          level = 8,
          hidden = false,
          upgrade = true,
          type = "technology"
        }
      }
    },
    ["py-coal"] = {
      requires = {
        pycoalprocessing = "3.0.44"
      },
      public = {
        "braking-force-8",
        "inserter-capacity-bonus-8",
        "laser-shooting-speed-8",
        "recipe-prod-research_advanced_circuit-1",
        "recipe-prod-research_batteries-1",
        "recipe-prod-research_belts-1",
        "recipe-prod-research_bullets-1",
        "recipe-prod-research_cannon_shooting_speed-1",
        "recipe-prod-research_character_crafting_speed-1",
        "recipe-prod-research_character_mining_speed-1",
        "recipe-prod-research_character_reach-1",
        "recipe-prod-research_character_walking_speed-1",
        "recipe-prod-research_concrete-1",
        "recipe-prod-research_copper-1",
        "recipe-prod-research_copper_cable-1",
        "recipe-prod-research_electric_energy-1",
        "recipe-prod-research_electric_engine-1",
        "recipe-prod-research_electric_shooting_speed-1",
        "recipe-prod-research_electronic_circuit-1",
        "recipe-prod-research_engine-1",
        "recipe-prod-research_explosives-1",
        "recipe-prod-research_flamethrower_shooting_speed-1",
        "recipe-prod-research_flying_robot_frame-1",
        "recipe-prod-research_furnace-1",
        "recipe-prod-research_gears-1",
        "recipe-prod-research_grenades-1",
        "recipe-prod-research_heavy_ammo-1",
        "recipe-prod-research_inserters-1",
        "recipe-prod-research_inventory_capacity-1",
        "recipe-prod-research_iron-1",
        "recipe-prod-research_iron_sticks-1",
        "recipe-prod-research_lab_productivity-1",
        "recipe-prod-research_landfill-1",
        "recipe-prod-research_low_density_structure-1",
        "recipe-prod-research_lubricant_productivity-1",
        "recipe-prod-research_material_py_log-1",
        "recipe-prod-research_material_py_log-4",
        "recipe-prod-research_mining_drill-1",
        "recipe-prod-research_modules-1",
        "recipe-prod-research_plastic-1",
        "recipe-prod-research_processing_unit-1",
        "recipe-prod-research_rails-1",
        "recipe-prod-research_robot_battery-1",
        "recipe-prod-research_rocket_fuel-1",
        "recipe-prod-research_rocket_shooting_speed-1",
        "recipe-prod-research_rockets-1",
        "recipe-prod-research_science_pack_productivity-1",
        "recipe-prod-research_steel-1",
        "recipe-prod-research_sulfur-1",
        "recipe-prod-research_sulfuric_acid_productivity-1",
        "recipe-prod-research_walls-1",
        "research-speed-7",
        "weapon-shooting-speed-7",
        "worker-robots-storage-4"
      },
      primary = "recipe-prod-research_material_py_log-4",
      continuation = "laser-shooting-speed-8",
      finite = {
        early = "recipe-prod-research_material_py_log-1",
        tail = "recipe-prod-research_material_py_log-4",
        early_level = 3,
        tail_level = 5
      },
      preflight_names = {
        "recipe-prod-research_material_py_log-1",
        "recipe-prod-research_material_py_log-4",
        "laser-shooting-speed-8"
      },
      preflight = {
        ["recipe-prod-research_material_py_log-1"] = {
          name = "recipe-prod-research_material_py_log-1",
          localised_name = {
            "",
            {
              "description.productivity-bonus"
            },
            ": ",
            {
              "item-name.log"
            }
          },
          localised_description = {
            "technology-description.more-infinite-research.recipe_productivity"
          },
          icons = {
            {
              icon = "__pycoalprocessinggraphics__/graphics/icons/mip/log-01.png",
              icon_size = 64
            },
            {
              icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
              icon_size = 128,
              scale = 0.5,
              shift = {
                50,
                50
              },
              floating = true
            }
          },
          effects = {
            {
              type = "change-recipe-productivity",
              recipe = "log1",
              change = 0.02
            }
          },
          prerequisites = {
            "automation-science-pack",
            "wood-processing"
          },
          unit = {
            ingredients = {
              {
                "automation-science-pack",
                1
              }
            },
            count_formula = "200*2^(L-1)",
            time = 30
          },
          max_level = 3,
          order = "p[research_material_py_log]",
          level = 1,
          upgrade = true,
          type = "technology"
        },
        ["recipe-prod-research_material_py_log-4"] = {
          name = "recipe-prod-research_material_py_log-4",
          localised_name = {
            "",
            {
              "description.productivity-bonus"
            },
            ": ",
            {
              "item-name.log"
            }
          },
          localised_description = {
            "technology-description.more-infinite-research.recipe_productivity"
          },
          icons = {
            {
              icon = "__pycoalprocessinggraphics__/graphics/icons/mip/log-01.png",
              icon_size = 64
            },
            {
              icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
              icon_size = 128,
              scale = 0.5,
              shift = {
                50,
                50
              },
              floating = true
            }
          },
          effects = {
            {
              type = "change-recipe-productivity",
              recipe = "log1",
              change = 0.02
            }
          },
          prerequisites = {
            "automation-science-pack",
            "recipe-prod-research_material_py_log-1",
            "utility-science-pack",
            "wood-processing"
          },
          unit = {
            ingredients = {
              {
                "automation-science-pack",
                1
              },
              {
                "utility-science-pack",
                1
              }
            },
            count_formula = "1600+200*(L-4)",
            time = 30
          },
          max_level = 50000000,
          order = "p[research_material_py_log__continuation]",
          level = 4,
          upgrade = true,
          type = "technology"
        },
        ["laser-shooting-speed-8"] = {
          name = "laser-shooting-speed-8",
          localised_name = {
            "technology-name.laser-shooting-speed"
          },
          localised_description = {
            "technology-description.laser-shooting-speed"
          },
          icons = {
            {
              icon = "__base__/graphics/technology/laser-shooting-speed.png",
              icon_size = 256
            },
            {
              icon = "__core__/graphics/icons/technology/constants/constant-speed.png",
              icon_size = 128,
              scale = 0.5,
              shift = {
                50,
                50
              },
              floating = true
            }
          },
          effects = {
            {
              type = "gun-speed",
              ammo_category = "laser",
              modifier = 0.5
            }
          },
          prerequisites = {
            "laser-shooting-speed-6",
            "laser-shooting-speed-7",
            "utility-science-pack",
            "production-science-pack",
            "chemical-science-pack",
            "logistic-science-pack",
            "automation-science-pack",
            "military-science-pack"
          },
          unit = {
            ingredients = {
              {
                "utility-science-pack",
                1
              },
              {
                "production-science-pack",
                2
              },
              {
                "chemical-science-pack",
                3
              },
              {
                "logistic-science-pack",
                6
              },
              {
                "automation-science-pack",
                10
              },
              {
                "military-science-pack",
                3
              }
            },
            count_formula = "1025.15625*1.5^(L-8)",
            time = 120
          },
          max_level = "infinite",
          order = "autotech-[000239]-[laser-shooting-speed-7]",
          level = 8,
          hidden = false,
          upgrade = true,
          type = "technology"
        }
      }
    },
    ["py-alienlife-hightech"] = {
      requires = {
        pycoalprocessing = "3.0.44",
        pyalienlife = "3.0.67",
        pyhightech = "3.0.19"
      },
      public = {
        "braking-force-8",
        "inserter-capacity-bonus-8",
        "laser-shooting-speed-8",
        "recipe-prod-research_advanced_circuit-1",
        "recipe-prod-research_batteries-1",
        "recipe-prod-research_belts-1",
        "recipe-prod-research_breeding-1",
        "recipe-prod-research_bullets-1",
        "recipe-prod-research_cannon_shooting_speed-1",
        "recipe-prod-research_character_crafting_speed-1",
        "recipe-prod-research_character_mining_speed-1",
        "recipe-prod-research_character_reach-1",
        "recipe-prod-research_character_walking_speed-1",
        "recipe-prod-research_concrete-1",
        "recipe-prod-research_copper-1",
        "recipe-prod-research_copper_cable-1",
        "recipe-prod-research_electric_energy-1",
        "recipe-prod-research_electric_engine-1",
        "recipe-prod-research_electric_shooting_speed-1",
        "recipe-prod-research_electronic_circuit-1",
        "recipe-prod-research_engine-1",
        "recipe-prod-research_explosives-1",
        "recipe-prod-research_flamethrower_shooting_speed-1",
        "recipe-prod-research_flying_robot_frame-1",
        "recipe-prod-research_furnace-1",
        "recipe-prod-research_gears-1",
        "recipe-prod-research_grenades-1",
        "recipe-prod-research_heavy_ammo-1",
        "recipe-prod-research_inserters-1",
        "recipe-prod-research_inventory_capacity-1",
        "recipe-prod-research_iron-1",
        "recipe-prod-research_iron_sticks-1",
        "recipe-prod-research_lab_productivity-1",
        "recipe-prod-research_landfill-1",
        "recipe-prod-research_low_density_structure-1",
        "recipe-prod-research_lubricant_productivity-1",
        "recipe-prod-research_mining_drill-1",
        "recipe-prod-research_modules-1",
        "recipe-prod-research_plastic-1",
        "recipe-prod-research_processing_unit-1",
        "recipe-prod-research_rails-1",
        "recipe-prod-research_robot_battery-1",
        "recipe-prod-research_rocket_fuel-1",
        "recipe-prod-research_rocket_shooting_speed-1",
        "recipe-prod-research_rockets-1",
        "recipe-prod-research_science_pack_productivity-1",
        "recipe-prod-research_steel-1",
        "recipe-prod-research_sulfur-1",
        "recipe-prod-research_sulfuric_acid_productivity-1",
        "recipe-prod-research_supercapacitor-1",
        "recipe-prod-research_superconductor-1",
        "recipe-prod-research_walls-1",
        "research-speed-7",
        "weapon-shooting-speed-7",
        "worker-robots-storage-4"
      },
      primary = "recipe-prod-research_breeding-1",
      continuation = "laser-shooting-speed-8",
      finite = nil,
      preflight_names = {
        "recipe-prod-research_breeding-1",
        "recipe-prod-research_supercapacitor-1",
        "recipe-prod-research_superconductor-1",
        "laser-shooting-speed-8"
      },
      preflight = {
        ["recipe-prod-research_breeding-1"] = {
          name = "recipe-prod-research_breeding-1",
          localised_name = {
            "technology-name.more-infinite-research.research_breeding",
            {
              "technology-name.fish-breeding"
            }
          },
          localised_description = {
            "technology-description.more-infinite-research.recipe_productivity"
          },
          icons = {
            {
              icon = "__pyalienlifegraphics__/graphics/icons/fish.png",
              icon_size = 32
            },
            {
              icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
              icon_size = 128,
              scale = 0.5,
              shift = {
                50,
                50
              },
              floating = true
            }
          },
          effects = {
            {
              type = "change-recipe-productivity",
              recipe = "arqad-mk02-breeding",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "arqad-mk03-breeding",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "arqad-mk04-breeding",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "auog-pup-breeding-1",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "auog-pup-breeding-2",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "auog-pup-breeding-3",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "auog-pup-breeding-4",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "auog-pup-breeding-5",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "bhoddos-culture-mk01",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "bhoddos-culture-mk02",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "bhoddos-culture-mk03",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "bhoddos-culture-mk04",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "bhoddos-spore-mk02-breeding",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "bhoddos-spore-mk03-breeding",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "bhoddos-spore-mk04-breeding",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "navens-culture-mk01",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "navens-culture-mk02",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "navens-culture-mk03",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "navens-culture-mk04",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "rennea-mk02-breeding",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "rennea-mk03-breeding",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "rennea-mk04-breeding",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "sponge-culture-mk01",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "sponge-culture-mk02",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "sponge-culture-mk03",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "sponge-culture-mk04",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "ulric-mk02-breeding",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "ulric-mk03-breeding",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "ulric-mk04-breeding",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "yaedols-culture-mk01",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "yaedols-culture-mk02",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "yaedols-culture-mk03",
              change = 0.1
            },
            {
              type = "change-recipe-productivity",
              recipe = "yaedols-culture-mk04",
              change = 0.1
            }
          },
          prerequisites = {
            "automation-science-pack",
            "logistic-science-pack",
            "chemical-science-pack",
            "production-science-pack"
          },
          unit = {
            ingredients = {
              {
                "automation-science-pack",
                1
              },
              {
                "logistic-science-pack",
                1
              },
              {
                "chemical-science-pack",
                1
              },
              {
                "production-science-pack",
                1
              }
            },
            count_formula = "8000*2^(L-1)",
            time = 60
          },
          max_level = "infinite",
          order = "p[research_breeding]",
          level = 1,
          upgrade = true,
          type = "technology"
        },
        ["recipe-prod-research_supercapacitor-1"] = {
          name = "recipe-prod-research_supercapacitor-1",
          localised_name = {
            "technology-name.more-infinite-research.research_supercapacitor",
            {
              "item-name.supercapacitor"
            }
          },
          localised_description = {
            "technology-description.more-infinite-research.recipe_productivity"
          },
          icons = {
            {
              icon = "__pyhightechgraphics__/graphics/technology/supercapacitor.png",
              icon_size = 128
            },
            {
              icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
              icon_size = 128,
              scale = 0.5,
              shift = {
                50,
                50
              },
              floating = true
            }
          },
          effects = {
            {
              type = "change-recipe-productivity",
              recipe = "supercapacitor",
              change = 0.1
            }
          },
          prerequisites = {
            "automation-science-pack",
            "logistic-science-pack",
            "chemical-science-pack",
            "production-science-pack"
          },
          unit = {
            ingredients = {
              {
                "automation-science-pack",
                1
              },
              {
                "logistic-science-pack",
                1
              },
              {
                "chemical-science-pack",
                1
              },
              {
                "production-science-pack",
                1
              }
            },
            count_formula = "8000*2^(L-1)",
            time = 60
          },
          max_level = "infinite",
          order = "p[research_supercapacitor]",
          level = 1,
          upgrade = true,
          type = "technology"
        },
        ["recipe-prod-research_superconductor-1"] = {
          name = "recipe-prod-research_superconductor-1",
          localised_name = {
            "technology-name.more-infinite-research.research_superconductor",
            {
              "item-name.superconductor"
            }
          },
          localised_description = {
            "technology-description.more-infinite-research.recipe_productivity"
          },
          icons = {
            {
              icon = "__pyhightechgraphics__/graphics/technology/superconductor.png",
              icon_size = 128
            },
            {
              icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
              icon_size = 128,
              scale = 0.5,
              shift = {
                50,
                50
              },
              floating = true
            }
          },
          effects = {
            {
              type = "change-recipe-productivity",
              recipe = "superconductor",
              change = 0.1
            }
          },
          prerequisites = {
            "automation-science-pack",
            "logistic-science-pack",
            "chemical-science-pack",
            "production-science-pack"
          },
          unit = {
            ingredients = {
              {
                "automation-science-pack",
                1
              },
              {
                "logistic-science-pack",
                1
              },
              {
                "chemical-science-pack",
                1
              },
              {
                "production-science-pack",
                1
              }
            },
            count_formula = "8000*2^(L-1)",
            time = 60
          },
          max_level = "infinite",
          order = "p[research_superconductor]",
          level = 1,
          upgrade = true,
          type = "technology"
        },
        ["laser-shooting-speed-8"] = {
          name = "laser-shooting-speed-8",
          localised_name = {
            "technology-name.laser-shooting-speed"
          },
          localised_description = {
            "technology-description.laser-shooting-speed"
          },
          icons = {
            {
              icon = "__base__/graphics/technology/laser-shooting-speed.png",
              icon_size = 256
            },
            {
              icon = "__core__/graphics/icons/technology/constants/constant-speed.png",
              icon_size = 128,
              scale = 0.5,
              shift = {
                50,
                50
              },
              floating = true
            }
          },
          effects = {
            {
              type = "gun-speed",
              ammo_category = "laser",
              modifier = 0.5
            }
          },
          prerequisites = {
            "laser-shooting-speed-6",
            "laser-shooting-speed-7",
            "utility-science-pack",
            "py-science-pack-4",
            "production-science-pack",
            "py-science-pack-3",
            "chemical-science-pack",
            "py-science-pack-2",
            "logistic-science-pack",
            "py-science-pack-1",
            "automation-science-pack",
            "military-science-pack",
            "space-science-pack"
          },
          unit = {
            ingredients = {
              {
                "utility-science-pack",
                1
              },
              {
                "py-science-pack-4",
                2
              },
              {
                "production-science-pack",
                3
              },
              {
                "py-science-pack-3",
                6
              },
              {
                "chemical-science-pack",
                10
              },
              {
                "py-science-pack-2",
                20
              },
              {
                "logistic-science-pack",
                30
              },
              {
                "py-science-pack-1",
                60
              },
              {
                "automation-science-pack",
                100
              },
              {
                "military-science-pack",
                20
              },
              {
                "space-science-pack",
                1
              }
            },
            count_formula = "1025.15625*1.5^(L-8)",
            time = 120
          },
          max_level = "infinite",
          order = "autotech-[000779]-[laser-shooting-speed-7]",
          level = 8,
          hidden = false,
          upgrade = true,
          type = "technology"
        }
      }
    }
  }
}
