"""Independent coverage for retained MIR research locale entries."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
LOCALE_ROOT = ROOT / "source" / "locale"
PUBLISHED_B6_ARCHIVE_SHA256 = "B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852"
NEW_ENGLISH_ONLY_KEY = "more-infinite-research.recipe_productivity"
NEW_ENGLISH_ONLY_VALUE = "Recipe productivity"
REFERENCE_PATTERN = re.compile(
    r"(?P<section>technology-name|technology-description|modifier-description)\.more-infinite-research\.(?P<key>[a-z0-9_]+)"
)

# These are the finite active source references present in B6. The per-locale
# projected hashes below pin their historical values without making a local B6
# archive a CI dependency.
B6_RETAINED_KEYS = {
    'modifier-description': (
        'more-infinite-research.agricultural_growth_speed',
        'more-infinite-research.spoilage_preservation',
    ),
    'technology-description': (
        'more-infinite-research.agricultural_growth_speed',
        'more-infinite-research.cargo_bay_unloading_distance',
        'more-infinite-research.cargo_landing_pad_count',
        'more-infinite-research.direct_effect',
        'more-infinite-research.electric_shooting_speed',
        'more-infinite-research.flamethrower_shooting_speed',
        'more-infinite-research.lab_productivity',
        'more-infinite-research.recipe_productivity',
        'more-infinite-research.spoilage_preservation',
    ),
    'technology-name': (
        'more-infinite-research.research_advanced_circuit',
        'more-infinite-research.research_agricultural_growth_speed',
        'more-infinite-research.research_armor_components',
        'more-infinite-research.research_artificial_soil',
        'more-infinite-research.research_bacteria_cultivation',
        'more-infinite-research.research_batteries',
        'more-infinite-research.research_belts',
        'more-infinite-research.research_bioflux',
        'more-infinite-research.research_breeding',
        'more-infinite-research.research_bullets',
        'more-infinite-research.research_cannon_shooting_speed',
        'more-infinite-research.research_capture_robot_rockets',
        'more-infinite-research.research_carbon',
        'more-infinite-research.research_carbon_fiber',
        'more-infinite-research.research_cargo_bay_unloading_distance',
        'more-infinite-research.research_cargo_landing_pad_count',
        'more-infinite-research.research_character_crafting_speed',
        'more-infinite-research.research_character_mining_speed',
        'more-infinite-research.research_character_reach',
        'more-infinite-research.research_character_walking_speed',
        'more-infinite-research.research_concrete',
        'more-infinite-research.research_copper',
        'more-infinite-research.research_copper_cable',
        'more-infinite-research.research_electric_energy',
        'more-infinite-research.research_electric_engine',
        'more-infinite-research.research_electric_shooting_speed',
        'more-infinite-research.research_electronic_circuit',
        'more-infinite-research.research_engine',
        'more-infinite-research.research_explosives',
        'more-infinite-research.research_flamethrower_shooting_speed',
        'more-infinite-research.research_flying_robot_frame',
        'more-infinite-research.research_furnace',
        'more-infinite-research.research_gears',
        'more-infinite-research.research_grenades',
        'more-infinite-research.research_heavy_ammo',
        'more-infinite-research.research_holmium',
        'more-infinite-research.research_ice',
        'more-infinite-research.research_inserters',
        'more-infinite-research.research_inventory_capacity',
        'more-infinite-research.research_iron',
        'more-infinite-research.research_iron_sticks',
        'more-infinite-research.research_lab_productivity',
        'more-infinite-research.research_landfill',
        'more-infinite-research.research_lithium',
        'more-infinite-research.research_low_density_structure',
        'more-infinite-research.research_lubricant_productivity',
        'more-infinite-research.research_mining_drill',
        'more-infinite-research.research_modules',
        'more-infinite-research.research_molten_metals',
        'more-infinite-research.research_nutrients',
        'more-infinite-research.research_oil_cracking_productivity',
        'more-infinite-research.research_oil_processing_productivity',
        'more-infinite-research.research_plastic',
        'more-infinite-research.research_platform',
        'more-infinite-research.research_processing_unit',
        'more-infinite-research.research_quantum_processor',
        'more-infinite-research.research_rails',
        'more-infinite-research.research_robot_battery',
        'more-infinite-research.research_rocket_fuel',
        'more-infinite-research.research_rocket_shooting_speed',
        'more-infinite-research.research_rockets',
        'more-infinite-research.research_science_pack_productivity',
        'more-infinite-research.research_spoilage_preservation',
        'more-infinite-research.research_steel',
        'more-infinite-research.research_sulfur',
        'more-infinite-research.research_sulfuric_acid_productivity',
        'more-infinite-research.research_supercapacitor',
        'more-infinite-research.research_superconductor',
        'more-infinite-research.research_thruster_fuel_productivity',
        'more-infinite-research.research_thruster_oxidizer_productivity',
        'more-infinite-research.research_tungsten',
        'more-infinite-research.research_walls',
    ),
}

# The current laboratory wording intentionally superseded the older B6 wording;
# keep it rather than overwriting an existing translation during restoration.
CURRENT_TRANSLATION_OVERRIDES = {
    'de': {
        'technology-name.more-infinite-research.research_lab_productivity': 'Laborproduktivität',
    },
    'en': {
        'technology-name.more-infinite-research.research_lab_productivity': 'Laboratory productivity',
    },
}

EXPECTED_RETAINED_PROJECTION_SHA256 = {
    'af': 'CB8F1EEEEBA24911BAC1E2B4A909C6698736BE14F50734D57EB86E86BD4F3817',
    'ar': '09F2DD177C5A1F1660E7456B895B01723E0ED93F1B924D7539CDCD492CAFDCDE',
    'be': '7B90B6A5B398078C0D129C61A80F4592065A74CEB70D23A0D58AC4186635ACD9',
    'bg': 'ACF1BD6CD53BADEA0C846D95A34E8E362F93B8F17290AE151EE8BE5EE3428667',
    'ca': '8518017BBC531975B95EC2E51A51C24CDBFB708FF7FC08F46176DF93AB76EE36',
    'cs': 'F1AC9E1D846B019FEB48250265F47E119C59CE83927B681F27BBAC9BB71DF748',
    'da': '2311136C0A32F7B634883B1C64E270C2B0CFE02763D210C6EB5CA13F3966B34F',
    'de': '7D20D8F6B0F5F3940F281B00166991DEFB6FB11B2B9EC5756E175FE008B53745',
    'el': 'A55E1BDA8B3ADBB87A8FC1FDB5BADB388F257FAD9AB878F4898D6663FD85A3D3',
    'en': 'A603DADA9F23D75D5F33856440A9EDDA4F130936ACE5FCEFD37C8E58BE1BD5E9',
    'eo': '71921D7C3E3BA33AC66C9D210D2DED284D63FE27F045120E48A62D1E8C5C2E15',
    'es-ES': '90CF7F1A69A6B8752FCFC941DE4D03B0DA64912BE46A8718AF1BAFF414544414',
    'et': '06EAEAB3503214555D78DF2DC605D00C5DE4448E49214DFC98E4DC79D542486F',
    'eu': 'C8882CB42E037001CDFB32F05FE12A4FAEC2EF76F5794FB8E814D33BD9956B67',
    'fa': '2A63E43A51C4E8A69080CF3EC4EDF358EDA123856342241D62BB81979C60B9F2',
    'fi': '9CC78CD89DF4EC1144F7E918C5880EF8E62EA1EC5FCF5FF3309703B6371DF204',
    'fil': '8CBCF20F5AA737D1CEF561095F7A11BE6C74EF1EB423F8FCABC0B2ED35474A62',
    'fr': '9DAEF3458BC060FB69412F0672244543BCDB987D6F8EA6B6761DAB68A56B9D50',
    'fy-NL': '1605F30FA7620E67D67D813A88A44C6C8AD5613C8E6AA7AC0D4860E56A4E0BE7',
    'ga-IE': 'C92FF4B81D54BB28074AC146C7CA57D4CBE6DF3DD9C2FF40DA99EA9715CAE46B',
    'he': '8174E925CFD3D98F1E035D3164FBB40EC57A21C14C935D567FB28EDBA7CCE8F2',
    'hr': '890D9DA4DF192208C7BD25156F3ABFC50F3F3F0E4AA164F60C9DB08CDC5E558E',
    'hu': '819C4CD6CECAA50B1A31CC7222DFD7C24234E1B0B25CF67724148C9ACAFAB907',
    'id': 'B405C2950D47C3C08D42361164A127792806017EAE5E6E0D00EA3F78C5A780EA',
    'is': '7B43E6F532BEC0355ED1324ACF778CA957E75C3997541714B8D535D08AB04CDD',
    'it': 'C9C2D427501DF1FE54DB31C29789F673BE36223F754FA54667500C54EDBC7FC6',
    'ja': 'AB0ABD17FEC65EB343D28ED078B6CCBF0CE08C39E4A36504603ABCFBB7979723',
    'ka': 'AAFE6E67C125E0F0E67A1713044FE46E6B54D991B4A0CA8A85F3FC4D52B26C50',
    'kk': '0FC50462889B96240437B2E556FB71A105CACDBA8827198618FB5A56469F39BB',
    'ko': 'F938535D339FE0D65FEDDDB181B0C70AC8D51E3D6920934F1D1FA4B95E8D2815',
    'lt': '94E3DB188CE77886C757AD0800B8B3D07BF54CE74A61527B22503FC16087EFD0',
    'lv': '3F61CF90C2E27641DECDE4916C0C82E3BFC89BE58BDC177D60052B448455D2CB',
    'nl': '31727286BB1F7CE558D37E25D4E1C99F7D2E9F779F07DD32CB66CD37B8DE5C8B',
    'no': '5E7C0564458ADAD81B408417CF92C712AAD2845BB701975A54C3D8CCCDE703D8',
    'pl': '55E5004657EC7B7DCA4B6C91F25B6B5698EECE1E0D47132124D1D62ADC336A5E',
    'pt-BR': '1F81CC41E3465FCF632F4D2C2A1F4E300028E16DC97301847E4F88F253F2180A',
    'pt-PT': '3C118F4D81A5DE56E1AFC7F22D454017B7B194E31CBD7687572AEC14EFDDD43C',
    'ro': '56FDC6E14938315503985D118F59792C4323777F7E973756010A96DCA36F719D',
    'ru': 'DAE9832ED1B0D853898057B67AAFB29026A6A24AEB5D8B9597366368CFFD3BD1',
    'sk': 'D44A4C05E2C7AA67D218EFC32D9E6A37D3300D66951727F5718CE55B51BAEBB2',
    'sl': 'A6C8EFF7271E505A98A0FD56E964DCED2331BDBF7018CAD76C6441FC5953A073',
    'sq': 'BE6D35925B920939EDED7C0EC2F4609765FDA5F88098D63EAB0ECE09EED6870E',
    'sr': 'F228A108183FD797EB0F8B0E74EC217901273FF0E1A2E7BB4629BE5D7F999993',
    'sv-SE': '6C9D2C9D604F41DCBC652E8997CACAAD0460D6EEBDAB5B1D19E66C55E7E69C9E',
    'th': '4E0EABD5D6BCED1B66888E36176A101A364173F8FB32C968C4554955246A43F9',
    'tr': '50E9B3A18D7A90D5C97EEEF1215B16FB04EE17031F04C82CB7B9ABF18DEC8B99',
    'uk': 'A682B1DEB648AEED69E1947438ADB2A889C55CF9EE30EB9987B55C3E984488B7',
    'vi': 'A483C872173877CB51AB890F5FD6FF4D6926F2BEC1BF252D46A95CE72243F1AE',
    'zh-CN': '8F61CAEC02245B9BEF692405A42CA5E7FAEEDAA0EE22C0466F8964B8302A0354',
    'zh-TW': '52F95F49CE30190437EEBAA6B4D38999E3F0BA3E94EB692B27E936CE5CBBA5DD',
}

# These are the finite current material families which the Library availability
# view constructs through `row.family`. They have no B6 locale entries, so the
# English labels below are explicitly new display corrections rather than
# recovered translations.
COMPUTED_MATERIAL_FAMILY_SOURCES = (
    "source/presentation/availability.lua",
    "source/research/bob_angel_materials.lua",
    "source/research/bob_core_materials.lua",
    "source/research/bob_plates_materials.lua",
    "source/research/k2_imersite.lua",
    "source/research/k2_materials.lua",
    "source/research/py_materials.lua",
)
COMPUTED_MATERIAL_FAMILY_PATTERN = re.compile(r"research_material_[a-z_]+")
COMPUTED_MATERIAL_ENGLISH_NAMES = {
    "research_material_aluminium": "Aluminium productivity",
    "research_material_brass": "Brass productivity",
    "research_material_bronze": "Bronze productivity",
    "research_material_cobalt_steel": "Cobalt steel productivity",
    "research_material_copper_tungsten": "Copper tungsten productivity",
    "research_material_glass": "Glass productivity",
    "research_material_gold": "Gold productivity",
    "research_material_gunmetal": "Gunmetal productivity",
    "research_material_imersite": "Imersite productivity",
    "research_material_invar": "Invar productivity",
    "research_material_lead": "Lead productivity",
    "research_material_nickel": "Nickel productivity",
    "research_material_nitinol": "Nitinol productivity",
    "research_material_platinum": "Platinum productivity",
    "research_material_py_log": "Log productivity",
    "research_material_rare_metals": "Rare metals productivity",
    "research_material_silicon": "Silicon productivity",
    "research_material_silver": "Silver productivity",
    "research_material_tin": "Tin productivity",
    "research_material_titanium": "Titanium productivity",
    "research_material_zinc": "Zinc productivity",
}


def parse_cfg_text(text: str, label: str) -> dict[str, dict[str, str]]:
    sections: dict[str, dict[str, str]] = {}
    current: str | None = None
    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            sections.setdefault(current, {})
            continue
        if current is None or "=" not in raw_line:
            continue
        key, value = raw_line.split("=", 1)
        if key in sections[current]:
            raise ValueError(f"duplicate locale key {current}.{key} at {label}:{line_number}")
        sections[current][key] = value
    return sections


def parse_cfg(path: Path) -> dict[str, dict[str, str]]:
    return parse_cfg_text(path.read_text(encoding="utf-8"), str(path))


def active_source_references() -> set[str]:
    references: set[str] = set()
    for path in (ROOT / "source").rglob("*.lua"):
        for match in REFERENCE_PATTERN.finditer(path.read_text(encoding="utf-8")):
            references.add(f"{match.group('section')}.more-infinite-research.{match.group('key')}")
    return references


def computed_material_families() -> set[str]:
    families: set[str] = set()
    for relative_path in COMPUTED_MATERIAL_FAMILY_SOURCES:
        text = (ROOT / relative_path).read_text(encoding="utf-8")
        for match in COMPUTED_MATERIAL_FAMILY_PATTERN.finditer(text):
            family = match.group(0)
            if not family.endswith("__continuation"):
                families.add(family)
    return families


def retained_projection(sections: dict[str, dict[str, str]]) -> dict[str, str]:
    projection: dict[str, str] = {}
    for section, keys in B6_RETAINED_KEYS.items():
        for key in keys:
            projection[f"{section}.{key}"] = sections[section][key]
    return projection


class LocaleCatalogueTests(unittest.TestCase):
    def test_source_reference_coverage_is_finite_and_explicit(self) -> None:
        expected = {
            f"{section}.{key}"
            for section, keys in B6_RETAINED_KEYS.items()
            for key in keys
        }
        expected.add(f"technology-name.{NEW_ENGLISH_ONLY_KEY}")
        self.assertEqual(active_source_references(), expected)

    def test_all_locales_restore_the_pinned_b6_projection_without_duplicates(self) -> None:
        locale_paths = sorted(LOCALE_ROOT.glob("*/more-infinite-research.cfg"))
        self.assertEqual({path.parent.name for path in locale_paths}, set(EXPECTED_RETAINED_PROJECTION_SHA256))
        for path in locale_paths:
            language = path.parent.name
            sections = parse_cfg(path)
            projection = retained_projection(sections)
            for full_key, expected in CURRENT_TRANSLATION_OVERRIDES.get(language, {}).items():
                self.assertEqual(projection[full_key], expected, f"{language}: {full_key}")
            actual = hashlib.sha256(
                json.dumps(projection, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
            ).hexdigest().upper()
            self.assertEqual(actual, EXPECTED_RETAINED_PROJECTION_SHA256[language], language)

    def test_mining_drill_and_material_family_labels_have_independent_historical_values(self) -> None:
        english = parse_cfg(LOCALE_ROOT / "en" / "more-infinite-research.cfg")
        german = parse_cfg(LOCALE_ROOT / "de" / "more-infinite-research.cfg")
        self.assertEqual(
            english["technology-name"]["more-infinite-research.research_mining_drill"],
            "Mining-drill manufacturing productivity",
        )
        self.assertEqual(
            german["technology-name"]["more-infinite-research.research_mining_drill"],
            "Erzförderer-Produktivität",
        )
        self.assertEqual(
            english["technology-name"]["more-infinite-research.research_steel"],
            "Steel plate productivity",
        )

    def test_hidden_k2_state_carrier_has_the_explicitly_new_english_title_only(self) -> None:
        english = parse_cfg(LOCALE_ROOT / "en" / "more-infinite-research.cfg")
        self.assertEqual(english["technology-name"][NEW_ENGLISH_ONLY_KEY], NEW_ENGLISH_ONLY_VALUE)
        for path in sorted(LOCALE_ROOT.glob("*/more-infinite-research.cfg")):
            if path.parent.name == "en":
                continue
            sections = parse_cfg(path)
            self.assertNotIn(NEW_ENGLISH_ONLY_KEY, sections.get("technology-name", {}), path.parent.name)

    def test_computed_material_family_labels_are_finite_and_english_only(self) -> None:
        self.assertEqual(computed_material_families(), set(COMPUTED_MATERIAL_ENGLISH_NAMES))
        english = parse_cfg(LOCALE_ROOT / "en" / "more-infinite-research.cfg")
        names = english["technology-name"]
        for family, expected in COMPUTED_MATERIAL_ENGLISH_NAMES.items():
            self.assertEqual(names[f"more-infinite-research.{family}"], expected, family)
        for path in sorted(LOCALE_ROOT.glob("*/more-infinite-research.cfg")):
            if path.parent.name == "en":
                continue
            names = parse_cfg(path).get("technology-name", {})
            for family in COMPUTED_MATERIAL_ENGLISH_NAMES:
                self.assertNotIn(f"more-infinite-research.{family}", names, path.parent.name)

    def test_parser_refuses_duplicate_or_conflicting_locale_keys(self) -> None:
        with self.assertRaisesRegex(ValueError, "duplicate locale key"):
            parse_cfg_text("[technology-name]\nkey=first\nkey=second\n", "synthetic")
if __name__ == "__main__":
    unittest.main()
