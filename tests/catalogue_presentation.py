"""Explicit presentation changes over independent published catalogue rows."""


BASE_LITERAL_TITLES = {
    "recipe-prod-research_mining_drill-1": ("research_mining_drill", "electric-mining-drill"),
    "recipe-prod-research_walls-1": ("research_walls", "stone-wall"),
}


def expected_base_presentation_rows(captured_rows):
    """Keep captured rows intact and apply only the reviewed LocalisedStrings."""
    expected = dict(captured_rows)
    for technology, (title, former_item) in BASE_LITERAL_TITLES.items():
        row = captured_rows.get(technology, {})
        title_key = "technology-name.more-infinite-research." + title
        if row.get("localised_name") != [title_key, ["item-name." + former_item]]:
            raise AssertionError(f"captured Base presentation changed: {technology}")
        expected[technology] = {**row, "localised_name": [title_key]}

    drill = expected["recipe-prod-research_mining_drill-1"]
    generic_description = ["technology-description.more-infinite-research.recipe_productivity"]
    if drill.get("localised_description") != generic_description:
        raise AssertionError("published oracle changed its captured mining drill description")
    drill["localised_description"] = [
        "", generic_description, " ", ["technology-description.more-infinite-research.mining_drill_extraction"],
    ]
    return expected
