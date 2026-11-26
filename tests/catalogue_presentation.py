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

    drill_id = "recipe-prod-research_mining_drill-1"
    expected[drill_id] = expected_drill_extraction_row(expected[drill_id])
    return expected


def expected_drill_extraction_row(captured):
    """Add the reviewed extraction guidance to the captured recipe description."""
    generic_description = ["technology-description.more-infinite-research.recipe_productivity"]
    if captured.get("localised_description") != generic_description:
        raise AssertionError("published oracle changed its captured mining drill description")
    return {**captured, "localised_description": [
        "", generic_description, " ", ["technology-description.more-infinite-research.mining_drill_extraction"],
    ]}
