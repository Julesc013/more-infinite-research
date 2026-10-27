"""Independent expected rows for MIR5's private native-credit carriers.

These assertions live with the host controls rather than player source.  They
keep the frozen published catalogue as the public-output oracle and validate
the twelve deliberately added signed carrier pairs and three historical module
credit holders field-for-field.
"""

NATIVE_CREDIT_DESCRIPTORS = (
    ("research_copper", "recipe-prod-research_copper-1", "copper-plate"),
    ("research_iron", "recipe-prod-research_iron-1", "iron-plate"),
    ("research_breeding", "recipe-prod-research_breeding-1", "fish-breeding"),
    ("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "advanced-oil-processing"),
    ("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "basic-oil-processing"),
    ("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "coal-liquefaction"),
    ("research_bullets", "recipe-prod-research_bullets-1", "firearm-magazine"),
    ("research_grenades", "recipe-prod-research_grenades-1", "grenade"),
    ("research_lubricant_productivity", "recipe-prod-research_lubricant_productivity-1", "lubricant"),
    ("research_breeding", "recipe-prod-research_breeding-1", "pentapod-egg"),
    ("research_concrete", "recipe-prod-research_concrete-1", "stone-brick"),
    ("research_sulfuric_acid_productivity", "recipe-prod-research_sulfuric_acid_productivity-1", "sulfuric-acid"),
)
NATIVE_CREDIT_DEFAULT_SCALAR = 0.1
NATIVE_CREDIT_ICON = "__base__/graphics/technology/automation-1.png"


def native_credit_carrier_rows(public_rows, captured_recipes):
    """Build exact dormant pairs for the finite named mains and present recipes.

    A foreign provider or recipe replacement can exclude a named recipe from
    its main row. The carrier still exists with a false initial inclusion;
    runtime accounting cannot invent an earned contribution from that state.
    A present effect must retain its exact default scalar and unique shape.
    """
    expected = {}
    for family, main_id, recipe in NATIVE_CREDIT_DESCRIPTORS:
        main = public_rows.get(main_id)
        if main is None or recipe not in captured_recipes:
            continue
        effects = [
            effect for effect in main["effects"]
            if effect.get("recipe") == recipe
        ]
        if effects and effects != [{
                "type": "change-recipe-productivity", "recipe": recipe,
                "change": NATIVE_CREDIT_DEFAULT_SCALAR}]:
            raise AssertionError(
                f"native credit has a conflicting captured default route: {main_id}:{recipe}"
            )
        for direction, change in (("positive", NATIVE_CREDIT_DEFAULT_SCALAR),
                                  ("negative", -NATIVE_CREDIT_DEFAULT_SCALAR)):
            name = f"mir-native-credit-{family}-{recipe}-{direction}"
            expected[name] = {
                "type": "technology",
                "name": name,
                "icon": NATIVE_CREDIT_ICON,
                "icon_size": 256,
                "level": 1,
                "upgrade": True,
                "hidden": True,
                "enabled": False,
                "visible_when_disabled": False,
                "max_level": "infinite",
                "order": f"zz[mir-native-credit]-{name}",
                "effects": [{
                    "type": "change-recipe-productivity",
                    "recipe": recipe,
                    "change": change,
                }],
                "unit": {
                    "count": 1,
                    "time": 1,
                    "ingredients": [["automation-science-pack", 1]],
                },
            }
    return expected


def legacy_module_credit_rows(captured_recipes):
    """Three fixed historical credits, independently checked after publication."""
    expected = {}
    for recipe in ("speed-module", "productivity-module", "efficiency-module"):
        if recipe not in captured_recipes:
            continue
        name = "mir-legacy-module-credit-" + recipe
        expected[name] = {
            "type": "technology", "name": name,
            "icon": "__base__/graphics/technology/module.png", "icon_size": 256,
            "level": 1, "upgrade": True, "hidden": True, "enabled": False,
            "visible_when_disabled": False, "max_level": "infinite",
            "order": "zz[mir-legacy-module-credit]-" + name,
            "effects": [{"type": "change-recipe-productivity", "recipe": recipe, "change": .01}],
            "unit": {"count": 1, "time": 1, "ingredients": [["automation-science-pack", 1]]},
        }
    return expected


def current_native_credit_rows(public_rows, captured_recipes):
    return {**native_credit_carrier_rows(public_rows, captured_recipes),
            **(legacy_module_credit_rows(captured_recipes)
               if "recipe-prod-research_modules-1" in public_rows else {})}


def captured_public_productivity_recipes(public_rows):
    """Return the exact named productivity routes preserved by a capture."""
    return {
        effect["recipe"]
        for row in public_rows.values()
        for effect in row.get("effects", [])
        if effect.get("type") == "change-recipe-productivity"
    }


def split_public_and_native_credit_rows(rows):
    """Partition outputs without accepting unknown carrier identities."""
    public, credit = {}, {}
    for name, row in rows.items():
        destination = credit if name.startswith(("mir-native-credit-", "mir-legacy-module-credit-")) else public
        destination[name] = row
    return public, credit


def verified_public_rows(rows, captured_recipes):
    """Verify every private addition and return the remaining public rows.

    Callers retain their own immutable public oracle.  This helper makes an
    unexpected carrier an error rather than silently filtering it out.
    """
    public, credit = split_public_and_native_credit_rows(rows)
    expected = current_native_credit_rows(public, captured_recipes)
    if credit != expected:
        raise AssertionError("native-credit rows differ from the exact authored oracle")
    if set(rows) != set(public) | set(expected):
        raise AssertionError("data stage emitted an unaccounted native-credit row")
    return public
