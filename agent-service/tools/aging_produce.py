from strands import tool

from .strapi_client import strapi_get


@tool
def get_aging_produce() -> list[dict]:
    """Get produce Items (isProduce=true) whose freshnessState is "aging" or "spoiled".

    Returns:
        List of Strapi Item records.
    """
    items = []
    for state in ("aging", "spoiled"):
        items.extend(
            strapi_get(
                "/api/items",
                params={
                    "filters[isProduce][$eq]": "true",
                    "filters[freshnessState][$eq]": state,
                    "pagination[pageSize]": 100,
                },
            )
        )
    return items
